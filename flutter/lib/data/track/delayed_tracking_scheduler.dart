import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../background/workmanager_tasks.dart';
import '../database/app_database.dart';
import '../network/app_http_client.dart';
import 'delayed_tracking_store.dart';
import 'track_credential_store.dart';
import 'track_repository.dart';
import 'tracker_registry.dart';

/// Identifier of the one-off retry task registered with workmanager.
/// Mirrors Kotlin's `DelayedTrackingUpdateJob.TAG`.
const String delayedTrackingTaskName = 'mohyeong.delayed_tracking';

/// Kotlin gives up at `runAttemptCount > 3`. The Dart side of workmanager
/// never sees that counter, so [DelayedTrackingStore] keeps its own and the
/// scheduler resets it on every fresh enqueue.
const int _maxAttempts = 3;

/// Drains the delayed-tracking queue inside the background isolate. Invoked
/// from the shared [backgroundCallbackDispatcher]. 1:1 with Kotlin's
/// `DelayedTrackingUpdateJob.doWork`.
///
/// Returns `true` once the queue is empty (or we've exhausted our attempts)
/// and `false` while entries remain, which is what makes workmanager honour
/// the exponential backoff the scheduler registered.
Future<bool> runDelayedTrackingTask() async {
  const store = DelayedTrackingStore();
  try {
    final attempts = await store.readAttempts();
    if (attempts >= _maxAttempts) {
      // Stop burning retries. Entries stay queued on purpose — the next
      // failed push reschedules the job and resets the counter, and a push
      // that lands normally clears its own entry.
      return true;
    }
    await store.writeAttempts(attempts + 1);

    final items = await store.getItems();
    if (items.isEmpty) return true;

    final http = await AppHttpClient.instance();
    final db = AppDatabase();
    try {
      final tracks = TrackRepository(db);
      final registry = buildTrackerRegistry(
        credentials: TrackCredentialStore(),
        // No UI in this isolate: the key exists only because trackers hold
        // one for their OAuth webview, which a background push never opens.
        navigatorKey: GlobalKey<NavigatorState>(),
        dio: http.dio,
      );

      for (final item in items) {
        final track = await tracks.getById(item.trackId);
        if (track == null) {
          // Row is gone — manga deleted, or the tracker was unbound. Kotlin
          // drops the entry in exactly this case.
          await store.remove(item.trackId);
          continue;
        }
        final tracker = registry.byId(track.trackerId);
        if (tracker == null) continue;
        if (!await tracker.isLoggedIn) continue;
        // Nothing to say if the remote is already at or past this point.
        if (track.lastChapterRead >= item.lastChapterRead) {
          await store.remove(item.trackId);
          continue;
        }
        final updated = track.withProgress(item.lastChapterRead);
        try {
          await tracker.update(updated, didReadChapter: true);
          await tracks.upsert(updated);
          await store.remove(item.trackId);
        } catch (e) {
          // Still unreachable — leave it queued for the next attempt.
          if (kDebugMode) {
            debugPrint('delayed tracking push failed for ${item.trackId}: $e');
          }
        }
      }
    } finally {
      await db.close();
    }

    return (await store.getItems()).isEmpty;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('delayed tracking task failed: $e\n$st');
    }
    return false;
  }
}

/// UI-side façade over the retry task. 1:1 with Kotlin's
/// `DelayedTrackingUpdateJob.setupTask`.
class DelayedTrackingScheduler {
  const DelayedTrackingScheduler();

  /// Enqueues the drain. `replace` + an attempt-counter reset mirror Kotlin's
  /// `enqueueUniqueWork(REPLACE)`, where a fresh work request starts its
  /// `runAttemptCount` at zero: a brand-new failure deserves a full run of
  /// retries even if an older one already used them up.
  Future<void> setupTask() async {
    await const DelayedTrackingStore().writeAttempts(0);
    await ensureWorkmanagerInitialized();
    await Workmanager().registerOneOffTask(
      delayedTrackingTaskName,
      delayedTrackingTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }
}

final delayedTrackingSchedulerProvider =
    Provider<DelayedTrackingScheduler>((ref) => const DelayedTrackingScheduler());
