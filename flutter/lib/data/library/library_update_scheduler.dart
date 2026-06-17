import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../background/workmanager_tasks.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../database/app_database.dart';
import '../download/download_repository.dart';
import '../manga/manga_repository.dart';
import '../network/app_http_client.dart';
import '../notification/notification_service.dart';
import '../source/extension_repository.dart';
import '../source/installed_extension.dart';
import '../source/local_source_preferences.dart';
import 'library_update_preference.dart';
import 'library_updater.dart';

/// Identifier of the periodic library-update task registered with
/// workmanager. Used both for `registerPeriodicTask` and the matching
/// `cancelByUniqueName` call when the user changes the interval.
const String libraryUpdateTaskName = 'mohyeong.library_update';
const String libraryUpdateOneOffTaskName = 'mohyeong.library_update_once';

/// Runs the library sweep inside the background isolate. Invoked from the
/// shared [backgroundCallbackDispatcher] for both the periodic and one-off
/// task names. The callback runs in a fresh isolate (no Flutter UI state, no
/// Riverpod overrides) so every dependency is built from scratch. Returns
/// `false` on failure so workmanager honours its retry policy.
Future<bool> runLibraryUpdateTask() async {
  try {
    final http = await AppHttpClient.instance();
    final storage = await ExtensionStorage.create();
    final prefs = await SharedPreferences.getInstance();
    final localPrefs = LocalSourcePreferences(prefs);
    final extensions = ExtensionRepository(storage, http, localPrefs);
    // This isolate has its own plugin instance — initialise it so the
    // background sweep can post progress / new-chapter notifications just
    // like Mihon's LibraryUpdateJob.
    final notifications = NotificationService.instance;
    await notifications.init();
    // Spins up a fresh AppDatabase against the same on-disk file the UI
    // process uses (drift_flutter resolves it via path_provider).
    final db = AppDatabase();
    // Declared outside the try so the finally can close its connectivity
    // subscription.
    final downloads = DownloadRepository(extensions, http);
    try {
      final mangas = MangaRepository(db);
      final chapters = ChapterRepository(db);
      final categories = CategoryRepository(db);
      final updater = LibraryUpdater(
        mangas,
        chapters,
        extensions,
        categories,
        downloads,
      );
      final result = await updater.updateAll(
        onProgress: (p) {
          if (p.currentTitle == null) {
            notifications.cancelLibraryProgress();
          } else {
            notifications.showLibraryProgress(
              current: p.completed,
              total: p.total,
              title: p.currentTitle!,
            );
          }
        },
      );
      await notifications.cancelLibraryProgress();
      await notifications.showNewChapters(
        mangaCount: result.mangaWithNewChapters,
        chapterCount: result.newChapters,
      );
      // Bump the Updates-tab badge count (Mihon LibraryUpdateJob:
      // `newUpdatesCount.getAndSet { it + newChapters.size }`). Written
      // straight to SharedPreferences — this isolate has no Riverpod; the
      // UI provider picks the value up on next launch.
      if (result.newChapters > 0) {
        const key = '__APP_STATE_library_unseen_updates_count';
        await prefs.reload();
        await prefs.setInt(key, (prefs.getInt(key) ?? 0) + result.newChapters);
      }
      await notifications.showLibraryErrors(result.failures.length);
      // Auto-downloads (if enabled) were enqueued during the sweep; wait
      // for them to finish before tearing down the DB/HTTP client this
      // isolate built, otherwise in-flight page fetches would abort.
      await downloads.awaitIdle();
    } finally {
      // DownloadRepository registers a connectivity subscription in its
      // ctor — close it so the isolate doesn't leak the listener.
      await downloads.close();
      await extensions.close();
      await db.close();
    }
    return true;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('libraryUpdate background task failed: $e\n$st');
    }
    // Returning false lets workmanager honour its retry policy.
    return false;
  }
}

/// UI-side façade over the workmanager scheduling surface. Responsible for
/// translating the user's [LibraryUpdateInterval] preference into a
/// periodic-task registration.
class LibraryUpdateScheduler {
  LibraryUpdateScheduler();

  /// Boots the workmanager engine and registers (or removes) the periodic
  /// task to match [interval]. Idempotent — safe to call from app start
  /// and again after the user changes the preference.
  Future<void> reschedule(LibraryUpdateInterval interval) async {
    await ensureWorkmanagerInitialized();
    // Always cancel first so changing the cadence drops the old registration.
    await Workmanager().cancelByUniqueName(libraryUpdateTaskName);
    if (interval == LibraryUpdateInterval.manual) return;
    await Workmanager().registerPeriodicTask(
      libraryUpdateTaskName,
      libraryUpdateTaskName,
      frequency: Duration(hours: interval.hours),
      constraints: await _buildConstraints(),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Builds the workmanager [Constraints] from the user's device-restriction
  /// preference ([libraryUpdateDeviceRestrictionProvider]). Read straight from
  /// [SharedPreferences] so the same mapping applies whether called from the
  /// UI isolate or app start. Wi-Fi-only / not-metered both map to
  /// [NetworkType.unmetered] (Android treats Wi-Fi as unmetered); otherwise a
  /// plain connection is required. Charging adds `requiresCharging`. Mirrors
  /// Kotlin `LibraryUpdateJob.setupTask`'s constraint builder.
  Future<Constraints> _buildConstraints() async {
    final prefs = await SharedPreferences.getInstance();
    final restrictions =
        (prefs.getStringList('library_update_restriction') ??
                const [DeviceRestriction.onlyOnWifi])
            .toSet();
    final unmetered =
        restrictions.contains(DeviceRestriction.onlyOnWifi) ||
            restrictions.contains(DeviceRestriction.networkNotMetered);
    return Constraints(
      networkType: unmetered ? NetworkType.unmetered : NetworkType.connected,
      requiresCharging: restrictions.contains(DeviceRestriction.charging),
    );
  }

  /// Triggers a one-off library update via workmanager. Used by the
  /// "Update now" manual button. The same callback dispatcher runs the
  /// fetch — running it via workmanager (instead of in-process) means it
  /// continues even if the user backgrounds the app.
  Future<void> runOnce() async {
    await ensureWorkmanagerInitialized();
    await Workmanager().registerOneOffTask(
      libraryUpdateOneOffTaskName,
      libraryUpdateOneOffTaskName,
      constraints: await _buildConstraints(),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

final libraryUpdateSchedulerProvider =
    Provider<LibraryUpdateScheduler>((ref) => LibraryUpdateScheduler());
