import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// Trackers that are registered (so the UI lists them with the right id /
/// name / category) but whose API integration is deferred until after
/// v1.0 ships. Selecting "Log in" on any of these surfaces a clear
/// not-implemented error rather than failing silently.
///
/// Each is a separate class because Mihon assigns each a distinct id and
/// the UI keys behaviour off the runtime type.
class _StubTracker extends Tracker {
  _StubTracker({
    required this.credentials,
    required int id,
    required String name,
    required TrackerCategory category,
  }) : super(id, name, category);

  final TrackCredentialStore credentials;

  @override
  Future<bool> get isLoggedIn => credentials.isAuthenticated(id);

  @override
  Future<void> login() => throw TrackerException(
        '$name login is not yet implemented in this build.',
      );

  @override
  Future<void> logout() => credentials.clear(id);

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    throw TrackerException('$name search is not yet implemented.');
  }

  @override
  Future<Track> refresh(Track track) async {
    throw TrackerException('$name refresh is not yet implemented.');
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    throw TrackerException('$name update is not yet implemented.');
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    throw TrackerException('$name bind is not yet implemented.');
  }
}

class KitsuTracker extends _StubTracker {
  KitsuTracker({required super.credentials})
      : super(
          id: TrackerIds.kitsu,
          name: 'Kitsu',
          category: TrackerCategory.online,
        );
}

class ShikimoriTracker extends _StubTracker {
  ShikimoriTracker({required super.credentials})
      : super(
          id: TrackerIds.shikimori,
          name: 'Shikimori',
          category: TrackerCategory.online,
        );
}

class MangaUpdatesTracker extends _StubTracker {
  MangaUpdatesTracker({required super.credentials})
      : super(
          id: TrackerIds.mangaUpdates,
          name: 'MangaUpdates',
          category: TrackerCategory.online,
        );
}

class KomgaTracker extends _StubTracker {
  KomgaTracker({required super.credentials})
      : super(
          id: TrackerIds.komga,
          name: 'Komga',
          category: TrackerCategory.advanced,
        );

  @override
  bool get supportsServerUrl => true;
}

class SuwayomiTracker extends _StubTracker {
  SuwayomiTracker({required super.credentials})
      : super(
          id: TrackerIds.suwayomi,
          name: 'Suwayomi',
          category: TrackerCategory.advanced,
        );

  @override
  bool get supportsServerUrl => true;
}
