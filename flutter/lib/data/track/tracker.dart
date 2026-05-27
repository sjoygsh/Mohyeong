import 'package:dio/dio.dart';

import '../../domain/track/model/track.dart';
import '../../domain/track/model/tracker.dart';

/// Abstract base every tracker implementation plugs into. Equivalent to
/// Kotlin's `eu.kanade.tachiyomi.data.track.Tracker`. One singleton instance
/// per tracker is registered with the [TrackerRegistry]; the registry hands
/// them out by id.
abstract class Tracker {
  Tracker(this.id, this.name, this.category);

  /// Stable id, used as `manga_sync.sync_id`. See [TrackerIds].
  final int id;
  final String name;
  final TrackerCategory category;

  /// Whether the user is currently signed in. Trackers should source this
  /// from a [TrackCredentialStore] check.
  Future<bool> get isLoggedIn;

  /// Whether the tracker requires a server URL (Komga / Suwayomi). UIs use
  /// this to render an extra "Server" field in the login dialog.
  bool get supportsServerUrl => false;

  /// Whether the tracker supports private list entries (AniList, MAL). The
  /// manga details sheet shows a "Private" toggle when true.
  bool get supportsPrivateTracking => false;

  /// Triggers the login flow. Returns once authentication has completed and
  /// credentials have been persisted. Throws on failure or user cancellation.
  Future<void> login();

  /// Clears persisted credentials and logs out.
  Future<void> logout();

  /// Searches the tracker's catalog for [query] and returns hits the user
  /// can pick to bind.
  Future<List<TrackSearchResult>> search(String query);

  /// Looks up the live state of an already-bound entry on the tracker's
  /// servers. Returns the freshly-fetched [Track] so the UI can refresh.
  Future<Track> refresh(Track track);

  /// Pushes a local [Track] change (chapter read / status / score) up to the
  /// tracker's API. Returns the new state as the tracker confirms it.
  Future<Track> update(Track track, {bool didReadChapter = false});

  /// Creates a new manga_sync row by binding [mangaId] to [searchResult].
  /// Returns the initial Track with the remote state copied in.
  Future<Track> bind(int mangaId, TrackSearchResult searchResult);

  /// List of status codes the tracker understands. Used to populate the
  /// status dropdown in the tracking sheet.
  List<int> get supportedStatuses => const [
        TrackStatus.reading,
        TrackStatus.completed,
        TrackStatus.onHold,
        TrackStatus.dropped,
        TrackStatus.planToRead,
        TrackStatus.rereading,
      ];

  String getStatusName(int status) {
    switch (status) {
      case TrackStatus.reading:
        return 'Reading';
      case TrackStatus.completed:
        return 'Completed';
      case TrackStatus.onHold:
        return 'On hold';
      case TrackStatus.dropped:
        return 'Dropped';
      case TrackStatus.planToRead:
        return 'Plan to read';
      case TrackStatus.rereading:
        return 'Re-reading';
      default:
        return 'Unknown';
    }
  }

  /// Hand the tracker its dio so it can hit its remote API. Subclasses may
  /// install per-tracker interceptors (OAuth refresh, base URL prefix, ...).
  /// Default impl: no-op.
  void attachDio(Dio dio) {}
}

/// Common exception class for tracker-side failures. Wraps the response body
/// when available so the UI can surface a useful message.
class TrackerException implements Exception {
  TrackerException(this.message, {this.response});

  final String message;
  final String? response;

  @override
  String toString() {
    final r = response;
    if (r == null || r.isEmpty) return 'TrackerException: $message';
    return 'TrackerException: $message — $r';
  }
}

/// Thrown when a tracker method is invoked without credentials. The UI is
/// expected to surface a "log in first" prompt.
class TrackerNotAuthenticated extends TrackerException {
  TrackerNotAuthenticated(String trackerName)
      : super('$trackerName: not authenticated');
}
