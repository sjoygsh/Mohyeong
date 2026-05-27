import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/track/model/track.dart';
import '../../domain/track/model/tracker.dart';
import 'track_repository.dart';
import 'tracker_registry.dart';

/// Walks every bound track for a manga and pushes a new chapter number up
/// to the corresponding tracker's remote API. Best-effort: errors are
/// swallowed per-track so one offline tracker can't block the others.
///
/// Invoked from the reader / manga details screens after a chapter's
/// `read` flag flips to true. Equivalent to Mihon's
/// `DelayedTrackingUpdateJob` enqueue path (without the delay batching —
/// v1.0 keeps it simple and pushes immediately).
class TrackUpdater {
  TrackUpdater(this._repo, this._registry);

  final TrackRepository _repo;
  final TrackerRegistry _registry;

  Future<void> setLastChapterRead({
    required int mangaId,
    required double chapterNumber,
  }) async {
    final tracks = await _repo.getByMangaId(mangaId);
    for (final track in tracks) {
      final tracker = _registry.byId(track.trackerId);
      if (tracker == null) continue;
      if (track.lastChapterRead >= chapterNumber) continue;
      final updated = track.copyWith(
        lastChapterRead: chapterNumber,
        status: _shouldComplete(track, chapterNumber)
            ? TrackStatus.completed
            : (track.status == TrackStatus.planToRead
                ? TrackStatus.reading
                : track.status),
      );
      try {
        await tracker.update(updated, didReadChapter: true);
        await _repo.upsert(updated);
      } catch (_) {
        // Swallow — surfacing errors in the reader would be intrusive.
        // The next sync attempt will pick up the diff.
      }
    }
  }

  bool _shouldComplete(Track track, double newChapter) {
    final total = track.totalChapters;
    return total > 0 && newChapter >= total;
  }
}

final trackUpdaterProvider = Provider<TrackUpdater>((ref) {
  return TrackUpdater(
    ref.watch(trackRepositoryProvider),
    ref.watch(trackerRegistryProvider),
  );
});
