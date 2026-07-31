import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../background/workmanager_tasks.dart';
import '../database/app_database.dart';
import '../network/app_http_client.dart';
import '../../domain/track/model/track.dart';
import 'delayed_tracking_store.dart';
import 'track_credential_store.dart';
import 'tracker.dart';
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
  final http = await AppHttpClient.instance();
  final db = AppDatabase();
  try {
    final tracks = TrackRepository(db);
    final registry = buildTrackerRegistry(
      credentials: TrackCredentialStore(),
      // No UI in this isolate: the key exists only because trackers hold one
      // for their OAuth webview, which a background push never opens.
      navigatorKey: GlobalKey<NavigatorState>(),
      dio: http.dio,
    );
    return drainDelayedTracking(
      store: const DelayedTrackingStore(),
      getTrack: tracks.getById,
      trackerFor: registry.byId,
      upsert: tracks.upsert,
    );
  } finally {
    await db.close();
  }
}

/// The drain itself, with its dependencies passed in.
///
/// Split out from [runDelayedTrackingTask] because that function builds a
/// database, an HTTP client and a credential store off method channels, which
/// makes it unreachable from a test AND unverifiable by hand without a real
/// tracker account — the queue's whole point is what happens when a remote
/// push fails, which is the hardest thing to stage deliberately. Everything
/// below is decided by the arguments, so the interesting cases (row deleted,
/// logged out, remote already ahead, still unreachable) can be driven
/// directly.
///
/// Returns `true` once the queue is empty (or we've exhausted our attempts)
/// and `false` while entries remain, which is what makes workmanager honour
/// the exponential backoff the scheduler registered.
Future<bool> drainDelayedTracking({
  required DelayedTrackingStore store,
  required Future<Track?> Function(int trackId) getTrack,
  required Tracker? Function(int trackerId) trackerFor,
  required Future<void> Function(Track track) upsert,
  int maxAttempts = _maxAttempts,
}) async {
  try {
    final attempts = await store.readAttempts();
    if (attempts >= maxAttempts) {
      // Stop burning retries. Entries stay queued on purpose — the next
      // failed push reschedules the job and resets the counter, and a push
      // that lands normally clears its own entry.
      return true;
    }
    await store.writeAttempts(attempts + 1);

    final items = await store.getItems();
    if (items.isEmpty) return true;

    for (final item in items) {
      // The WHOLE item is guarded, not just the push. The live path promises
      // that one offline tracker can't block the others and the drain has to
      // promise the same: reading credentials here crosses a method channel
      // from a background isolate, so `isLoggedIn` is a realistic thrower,
      // and letting it escape would strand every remaining entry for the run.
      try {
        final track = await getTrack(item.trackId);
        if (track == null) {
          // Row is gone — manga deleted, or the tracker was unbound. Kotlin
          // drops the entry in exactly this case.
          await store.remove(item.trackId);
          continue;
        }
        final tracker = trackerFor(track.trackerId);
        if (tracker == null) continue;
        if (!await tracker.isLoggedIn) continue;
        // Nothing to say if the remote is already at or past this point.
        if (track.lastChapterRead >= item.lastChapterRead) {
          await store.remove(item.trackId);
          continue;
        }
        final updated = track.withProgress(item.lastChapterRead);
        await tracker.update(updated, didReadChapter: true);
        await upsert(updated);
        await store.remove(item.trackId);
      } catch (e) {
        // Still unreachable — leave it queued for the next attempt.
        if (kDebugMode) {
          debugPrint('delayed tracking push failed for ${item.trackId}: $e');
        }
      }
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
