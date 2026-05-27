/// Stable integer identifiers for each tracker. Match the Kotlin
/// `TrackerManager` ids byte-for-byte so a row in the existing `manga_sync`
/// table (`sync_id` column) opened by either app refers to the same tracker.
///
/// New trackers must add a new id without recycling old ones. Anything that
/// reads the table must be tolerant of unknown ids (treat as "tracker
/// uninstalled").
class TrackerIds {
  const TrackerIds._();

  static const int myAnimeList = 1;
  static const int aniList = 2;
  static const int kitsu = 3;
  static const int shikimori = 4;
  static const int mangaUpdates = 5;
  static const int komga = 6;
  static const int suwayomi = 7;
  // 8 was Bangumi in Mihon; intentionally skipped per architecture decision.
}

/// Visibility category shown in the trackers list UI. Mirrors Mihon's split
/// between "normal" online trackers (AniList, MAL, ...) and "advanced"
/// server-backed trackers (Komga, Suwayomi) that most users won't touch.
enum TrackerCategory {
  online,
  advanced,
}

/// Status codes used by trackers. The integer values match Mihon's
/// `TrackManager`-level normalisation so a track row written by either app
/// agrees on what the user's reading state is. Individual trackers translate
/// to/from their own API enums in [Tracker.update] / search responses.
///
/// Names are kept in sync with the labels shown in the manga details
/// tracking sheet.
class TrackStatus {
  const TrackStatus._();

  static const int reading = 1;
  static const int completed = 2;
  static const int onHold = 3;
  static const int dropped = 4;
  static const int planToRead = 5;
  static const int rereading = 6;
}

/// One search hit returned by a tracker's API. The user picks one to bind to
/// a local manga via [Tracker.bind].
class TrackSearchResult {
  const TrackSearchResult({
    required this.remoteId,
    required this.title,
    required this.totalChapters,
    required this.coverUrl,
    required this.summary,
    required this.publishingStatus,
    required this.publishingType,
    required this.startDate,
    required this.score,
    required this.remoteUrl,
  });

  /// The tracker-side id for the manga (e.g. AniList media id).
  final int remoteId;
  final String title;
  final int totalChapters;
  final String? coverUrl;
  final String? summary;
  final String? publishingStatus;
  final String? publishingType;
  final String? startDate;
  final double? score;
  final String remoteUrl;
}
