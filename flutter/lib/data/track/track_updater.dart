import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/tide/tide.dart';
import 'delayed_tracking_scheduler.dart';
import 'delayed_tracking_store.dart';
import 'track_preferences.dart';
import 'track_repository.dart';
import 'tracker_registry.dart';

/// Walks every bound track for a manga and pushes a new chapter number up
/// to the corresponding tracker's remote API. Errors are caught per-track so
/// one offline tracker can't block the others — but they are NOT discarded:
/// a failed push is queued in [DelayedTrackingStore] and a retry job is
/// scheduled, mirroring Mihon's `TrackChapter` + `DelayedTrackingUpdateJob`.
///
/// Invoked from the reader / manga details screens after a chapter's
/// `read` flag flips to true.
class TrackUpdater {
  TrackUpdater(this._ref, this._repo, this._registry);

  final Ref _ref;
  final TrackRepository _repo;
  final TrackerRegistry _registry;

  DelayedTrackingStore get _delayed => _ref.read(delayedTrackingStoreProvider);

  /// Pushes [chapterNumber] (or [volumeNumber] when the "track by volume"
  /// preference is on and a volume is recognised) up to every bound tracker.
  /// Mirrors Mihon `TrackChapter.await`: `progress = byVolume && volume != null
  /// ? volume : chapter`, skipping any tracker whose `lastChapterRead` already
  /// meets or exceeds that progress.
  Future<void> setLastChapterRead({
    required int mangaId,
    required double chapterNumber,
    double? volumeNumber,
  }) async {
    final byVolume = _ref.read(trackByVolumeProvider);
    final progress = (byVolume && volumeNumber != null && volumeNumber >= 0)
        ? volumeNumber
        : chapterNumber;
    final tracks = await _repo.getByMangaId(mangaId);
    var queued = false;
    for (final track in tracks) {
      final tracker = _registry.byId(track.trackerId);
      if (tracker == null) continue;
      if (track.lastChapterRead >= progress) continue;
      final updated = track.withProgress(progress);
      try {
        await tracker.update(updated, didReadChapter: true);
        await _repo.upsert(updated);
        // Landed — retire any older queued attempt for this track.
        await _delayed.remove(track.id);
      } catch (_) {
        // Raising this in the reader would be intrusive, but dropping it
        // would leave the tracker permanently under-reporting whenever the
        // failure lands on the last chapter nothing else follows. Queue it.
        await _delayed.add(track.id, progress);
        queued = true;
      }
    }
    // One enqueue for the whole manga, not one per failed tracker: the task
    // is unique-named with REPLACE, so N calls would just reset each other's
    // backoff.
    if (queued) {
      await _ref.read(delayedTrackingSchedulerProvider).setupTask();
    }
  }
}

final trackUpdaterProvider = Provider<TrackUpdater>((ref) {
  return TrackUpdater(
    ref,
    ref.watch(trackRepositoryProvider),
    ref.watch(trackerRegistryProvider),
  );
});

/// Mark-as-read tracker push gated by the `autoUpdateTrackOnMarkRead`
/// preference. Mirrors Mihon `MangaScreenModel.markChaptersRead`'s tracking
/// branch: NEVER → no push; ALWAYS → push + a "Trackers updated to chapter N"
/// toast; ASK → a "Update trackers to chapter N?" snackbar with an OK action
/// that performs the push. The push itself is skipped entirely when no bound
/// tracker is behind the new progress.
///
/// [chapterNumber] is the highest chapter number being marked read; the
/// confirm/confirmation copy always uses the chapter number (matching Mihon)
/// even when "track by volume" changes the value actually sent.
Future<void> trackOnMarkRead(
  WidgetRef ref,
  BuildContext context, {
  required int mangaId,
  required double chapterNumber,
  double? volumeNumber,
}) async {
  final state =
      AutoTrackState.fromKey(ref.read(autoUpdateTrackOnMarkReadProvider));
  if (state == AutoTrackState.never) return;

  final tracks = await ref.read(trackRepositoryProvider).getByMangaId(mangaId);
  if (tracks.isEmpty) return;

  final byVolume = ref.read(trackByVolumeProvider);
  final progress = (byVolume && volumeNumber != null && volumeNumber >= 0)
      ? volumeNumber
      : chapterNumber;
  final shouldPrompt = tracks.any((t) => progress > t.lastChapterRead);
  if (!shouldPrompt) return;

  final updater = ref.read(trackUpdaterProvider);

  if (state == AutoTrackState.always) {
    await updater.setLastChapterRead(
      mangaId: mangaId,
      chapterNumber: chapterNumber,
      volumeNumber: volumeNumber,
    );
    if (!context.mounted) return;
    TideToast.of(context)
        .show('Trackers updated to chapter ${chapterNumber.toInt()}');
    return;
  }

  // AutoTrackState.ask
  if (!context.mounted) return;
  TideToast.of(context).show(
    'Update trackers to chapter ${chapterNumber.toInt()}?',
    actionLabel: 'OK',
    onAction: () => unawaited(
      updater.setLastChapterRead(
        mangaId: mangaId,
        chapterNumber: chapterNumber,
        volumeNumber: volumeNumber,
      ),
    ),
  );
}
