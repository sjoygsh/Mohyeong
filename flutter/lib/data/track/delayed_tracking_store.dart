import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../base/base_preferences.dart';

/// One queued tracker push: the local track row and the progress that never
/// made it to the remote API.
class DelayedTrackingItem {
  const DelayedTrackingItem({
    required this.trackId,
    required this.lastChapterRead,
  });

  final int trackId;
  final double lastChapterRead;
}

/// Queue of tracker pushes that failed and still owe the remote API an
/// update. 1:1 with Mihon's `DelayedTrackingStore`.
///
/// Kotlin gets its own SharedPreferences *file* (`tracking_queue`); Dart's
/// `shared_preferences` exposes a single store, so entries are namespaced by
/// key prefix instead.
///
/// **The prefix starts with [appStatePrefix] deliberately.** A queued push is
/// THIS device's pending state: [trackId] is a local `manga_sync` row id, so
/// replaying another phone's queue would push its progress onto whatever rows
/// happen to hold those ids here. That prefix is exactly what the backup
/// creator and restorer already filter on, so the queue stays out of backups
/// on both ends without a second exclusion list to keep in sync.
class DelayedTrackingStore {
  const DelayedTrackingStore();

  static const String keyPrefix = '${appStatePrefix}tracking_queue_';

  /// Attempt counter for the retry job. Mihon leans on WorkManager's
  /// `runAttemptCount`, which the Dart side of workmanager never sees, so the
  /// count is kept here and reset every time the job is (re)scheduled.
  static const String attemptsKey = '${appStatePrefix}tracking_queue_attempts';

  /// Queues [lastChapterRead] for [trackId]. Only ever raises the stored
  /// value — Kotlin's `add` compares against the previous entry so a later
  /// failure at a LOWER chapter can't walk the queued progress backwards.
  Future<void> add(int trackId, double lastChapterRead) async {
    final prefs = await SharedPreferences.getInstance();
    // The drain runs in the workmanager isolate, which removes keys this
    // isolate's cache still holds; compare against disk, not that stale view,
    // or a re-failure at the same chapter would be silently dropped.
    await prefs.reload();
    final key = '$keyPrefix$trackId';
    final previous = (prefs.get(key) as num?)?.toDouble() ?? 0;
    if (lastChapterRead > previous) {
      await prefs.setDouble(key, lastChapterRead);
    }
  }

  /// Drops [trackId]'s entry — called after a push finally lands.
  Future<void> remove(int trackId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$keyPrefix$trackId');
  }

  Future<List<DelayedTrackingItem>> getItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final out = <DelayedTrackingItem>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(keyPrefix)) continue;
      final trackId = int.tryParse(key.substring(keyPrefix.length));
      if (trackId == null) continue;
      final value = (prefs.get(key) as num?)?.toDouble();
      if (value == null) continue;
      out.add(DelayedTrackingItem(trackId: trackId, lastChapterRead: value));
    }
    return out;
  }

  Future<int> readAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getInt(attemptsKey) ?? 0;
  }

  Future<void> writeAttempts(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(attemptsKey, value);
  }
}

final delayedTrackingStoreProvider =
    Provider<DelayedTrackingStore>((ref) => const DelayedTrackingStore());
