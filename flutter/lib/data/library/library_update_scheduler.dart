import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../chapter/chapter_repository.dart';
import '../database/app_database.dart';
import '../manga/manga_repository.dart';
import '../network/app_http_client.dart';
import '../source/extension_repository.dart';
import '../source/installed_extension.dart';
import 'library_update_preference.dart';
import 'library_updater.dart';

/// Identifier of the periodic library-update task registered with
/// workmanager. Used both for `registerPeriodicTask` and the matching
/// `cancelByUniqueName` call when the user changes the interval.
const String libraryUpdateTaskName = 'mohyeong.library_update';
const String libraryUpdateOneOffTaskName = 'mohyeong.library_update_once';

/// Background-callback entry point. Workmanager runs this in a fresh
/// isolate (so no Flutter UI state and no Riverpod overrides exist here) —
/// every dependency must be built from scratch.
///
/// Marked as a `vm:entry-point` so tree-shaking doesn't drop it.
@pragma('vm:entry-point')
void libraryUpdateCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != libraryUpdateTaskName && task != libraryUpdateOneOffTaskName) {
      return Future.value(true);
    }
    try {
      final http = await AppHttpClient.instance();
      final storage = await ExtensionStorage.create();
      final extensions = ExtensionRepository(storage, http);
      // Spins up a fresh AppDatabase against the same on-disk file the UI
      // process uses (drift_flutter resolves it via path_provider).
      final db = AppDatabase();
      try {
        final mangas = MangaRepository(db);
        final chapters = ChapterRepository(db);
        final updater = LibraryUpdater(mangas, chapters, extensions);
        await updater.updateAll();
      } finally {
        await extensions.close();
        await db.close();
      }
      return Future.value(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('libraryUpdate background task failed: $e\n$st');
      }
      // Returning false lets workmanager honour its retry policy.
      return Future.value(false);
    }
  });
}

/// UI-side façade over the workmanager scheduling surface. Responsible for
/// translating the user's [LibraryUpdateInterval] preference into a
/// periodic-task registration.
class LibraryUpdateScheduler {
  LibraryUpdateScheduler();

  bool _initialised = false;

  /// Boots the workmanager engine and registers (or removes) the periodic
  /// task to match [interval]. Idempotent — safe to call from app start
  /// and again after the user changes the preference.
  Future<void> reschedule(LibraryUpdateInterval interval) async {
    if (!_initialised) {
      await Workmanager().initialize(libraryUpdateCallbackDispatcher);
      _initialised = true;
    }
    // Always cancel first so changing the cadence drops the old registration.
    await Workmanager().cancelByUniqueName(libraryUpdateTaskName);
    if (interval == LibraryUpdateInterval.manual) return;
    await Workmanager().registerPeriodicTask(
      libraryUpdateTaskName,
      libraryUpdateTaskName,
      frequency: Duration(hours: interval.hours),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Triggers a one-off library update via workmanager. Used by the
  /// "Update now" manual button. The same callback dispatcher runs the
  /// fetch — running it via workmanager (instead of in-process) means it
  /// continues even if the user backgrounds the app.
  Future<void> runOnce() async {
    if (!_initialised) {
      await Workmanager().initialize(libraryUpdateCallbackDispatcher);
      _initialised = true;
    }
    await Workmanager().registerOneOffTask(
      libraryUpdateOneOffTaskName,
      libraryUpdateOneOffTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

final libraryUpdateSchedulerProvider =
    Provider<LibraryUpdateScheduler>((ref) => LibraryUpdateScheduler());
