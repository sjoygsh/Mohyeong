import 'tracker.dart';

/// Mirror of `tachiyomi.domain.track.model.Track`.
/// One row per (manga, tracker) pair, e.g. AniList, MyAnimeList, MangaUpdates.
class Track {
  const Track({
    required this.id,
    required this.mangaId,
    required this.trackerId,
    required this.remoteId,
    required this.libraryId,
    required this.title,
    required this.lastChapterRead,
    required this.totalChapters,
    required this.status,
    required this.score,
    required this.remoteUrl,
    required this.startDate,
    required this.finishDate,
    required this.private,
  });

  final int id;
  final int mangaId;
  final int trackerId;
  final int remoteId;
  final int? libraryId;
  final String title;
  final double lastChapterRead;
  final int totalChapters;
  final int status;
  final double score;
  final String remoteUrl;
  final int startDate;
  final int finishDate;
  final bool private;

  Track copyWith({
    int? id,
    int? mangaId,
    int? trackerId,
    int? remoteId,
    Object? libraryId = _sentinel,
    String? title,
    double? lastChapterRead,
    int? totalChapters,
    int? status,
    double? score,
    String? remoteUrl,
    int? startDate,
    int? finishDate,
    bool? private,
  }) {
    return Track(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      trackerId: trackerId ?? this.trackerId,
      remoteId: remoteId ?? this.remoteId,
      libraryId: identical(libraryId, _sentinel)
          ? this.libraryId
          : libraryId as int?,
      title: title ?? this.title,
      lastChapterRead: lastChapterRead ?? this.lastChapterRead,
      totalChapters: totalChapters ?? this.totalChapters,
      status: status ?? this.status,
      score: score ?? this.score,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      startDate: startDate ?? this.startDate,
      finishDate: finishDate ?? this.finishDate,
      private: private ?? this.private,
    );
  }

  /// This track advanced to [progress], with the status transition that
  /// implies: a series whose total is known and reached becomes `completed`,
  /// and a plan-to-read entry the user has actually started becomes
  /// `reading`. Every other status is left alone.
  ///
  /// Pure and shared on purpose — both the live push and the delayed-retry
  /// drain build their updated row through here, so a queued push that lands
  /// hours later writes exactly what the immediate one would have.
  Track withProgress(double progress) {
    final reachedEnd = totalChapters > 0 && progress >= totalChapters;
    return copyWith(
      lastChapterRead: progress,
      status: reachedEnd
          ? TrackStatus.completed
          : (status == TrackStatus.planToRead ? TrackStatus.reading : status),
    );
  }
}

const Object _sentinel = Object();
