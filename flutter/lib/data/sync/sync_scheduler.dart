import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import '../manga/excluded_scanlators_repository.dart';
import '../manga/scanlator_priority_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../background/workmanager_tasks.dart';
import '../backup/backup_creator.dart';
import '../backup/backup_restorer.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../database/app_database.dart';
import '../history/history_repository.dart';
import '../manga/manga_repository.dart';
import '../network/app_http_client.dart';
import '../source/source_repository.dart';
import '../track/track_repository.dart';
import 'sync_manager.dart';
import 'sync_preferences.dart';

/// Identifiers of the periodic / one-off data-sync tasks registered with
/// workmanager. Mirror Mihon's `SyncDataJob` TAG_AUTO / TAG_MANUAL split.
const String syncTaskName = 'mohyeong.sync';
const String syncOneOffTaskName = 'mohyeong.sync_once';

/// Runs a full bidirectional sync inside the background isolate. Invoked from
/// the shared [backgroundCallbackDispatcher] for both the periodic and one-off
/// task names. Builds [SyncManager] (and the backup creator/restorer it needs)
/// from scratch because the callback runs in a fresh isolate with no Riverpod.
/// Returns `false` on failure so workmanager honours its retry policy; a
/// no-op success when no service is configured, matching Kotlin's `doWork`.
Future<bool> runSyncTask() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final syncPrefs = SyncPreferences(prefs: prefs);
    if (syncPrefs.read().service == SyncService.none) return true;

    final http = await AppHttpClient.instance();
    final db = AppDatabase();
    try {
      final mangas = MangaRepository(db);
      final chapters = ChapterRepository(db);
      final categories = CategoryRepository(db);
      final history = HistoryRepository(db);
      final tracks = TrackRepository(db);
      final sources = SourceRepository(db);
      final excludedScanlators = ExcludedScanlatorsRepository(db);
      final scanlatorPriority = ScanlatorPriorityRepository(db);
      final creator = BackupCreator(
        database: db,
        mangaRepository: mangas,
        chapterRepository: chapters,
        categoryRepository: categories,
        historyRepository: history,
        trackRepository: tracks,
        sourceRepository: sources,
        excludedScanlatorsRepository: excludedScanlators,
        scanlatorPriorityRepository: scanlatorPriority,
      );
      final restorer = BackupRestorer(
        database: db,
        mangaRepository: mangas,
        chapterRepository: chapters,
        categoryRepository: categories,
        historyRepository: history,
        trackRepository: tracks,
        sourceRepository: sources,
        excludedScanlatorsRepository: excludedScanlators,
        scanlatorPriorityRepository: scanlatorPriority,
      );
      final manager = SyncManager(
        preferences: syncPrefs,
        creator: creator,
        restorer: restorer,
        http: http,
      );
      await manager.sync();
    } finally {
      await db.close();
    }
    return true;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('sync background task failed: $e\n$st');
    }
    return false;
  }
}

/// UI-side façade over the data-sync workmanager surface. Translates the
/// auto-sync preferences into a periodic-task registration. 1:1 with Mihon's
/// `SyncDataJob.setupTask` / `startNow`.
class SyncScheduler {
  SyncScheduler();

  /// Registers (or cancels) the periodic sync task. Cancels when auto-sync is
  /// off, the interval is non-positive, or no service is configured — matching
  /// Kotlin's `setupTask` guard (`enabled && service != NONE && interval > 0`).
  Future<void> reschedule({
    required bool enabled,
    required int intervalHours,
    required SyncService service,
  }) async {
    await ensureWorkmanagerInitialized();
    await Workmanager().cancelByUniqueName(syncTaskName);
    if (!enabled || intervalHours <= 0 || service == SyncService.none) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      syncTaskName,
      syncTaskName,
      frequency: Duration(hours: intervalHours),
      // Kotlin: CONNECTED + requiresBatteryNotLow for the periodic job.
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  /// Triggers a one-off sync via workmanager (the "Sync now" button). Mirrors
  /// Kotlin's `startNow`: CONNECTED constraint, keep an in-flight run rather
  /// than stacking a duplicate.
  Future<void> runOnce() async {
    await ensureWorkmanagerInitialized();
    await Workmanager().registerOneOffTask(
      syncOneOffTaskName,
      syncOneOffTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}

final syncSchedulerProvider =
    Provider<SyncScheduler>((ref) => SyncScheduler());
