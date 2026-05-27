import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted OAuth tokens / basic-auth credentials per tracker. Backed by
/// `flutter_secure_storage` so secrets land in the platform keystore /
/// keychain (and not plaintext SharedPreferences).
///
/// Each tracker stores at most three string fields:
///   * `<id>.access`   — OAuth access token, or basic-auth password.
///   * `<id>.refresh`  — OAuth refresh token (or null for basic-auth).
///   * `<id>.userdata` — JSON blob the tracker decides how to fill in:
///                       typically username + remote user id + serverUrl
///                       (for self-hosted trackers).
///
/// Trackers are NOT expected to touch the storage directly — they call into
/// the store via [readCredential]/[writeCredential]/[clear].
class TrackCredentialStore {
  TrackCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<TrackerCredential?> readCredential(int trackerId) async {
    final access = await _storage.read(key: _keyAccess(trackerId));
    if (access == null || access.isEmpty) return null;
    final refresh = await _storage.read(key: _keyRefresh(trackerId));
    final userdata = await _storage.read(key: _keyUserdata(trackerId));
    return TrackerCredential(
      accessToken: access,
      refreshToken: refresh,
      userdata: userdata,
    );
  }

  Future<void> writeCredential(
    int trackerId,
    TrackerCredential credential,
  ) async {
    await _storage.write(
      key: _keyAccess(trackerId),
      value: credential.accessToken,
    );
    await _storage.write(
      key: _keyRefresh(trackerId),
      value: credential.refreshToken,
    );
    await _storage.write(
      key: _keyUserdata(trackerId),
      value: credential.userdata,
    );
  }

  Future<void> clear(int trackerId) async {
    await _storage.delete(key: _keyAccess(trackerId));
    await _storage.delete(key: _keyRefresh(trackerId));
    await _storage.delete(key: _keyUserdata(trackerId));
  }

  Future<bool> isAuthenticated(int trackerId) async {
    final access = await _storage.read(key: _keyAccess(trackerId));
    return access != null && access.isNotEmpty;
  }

  String _keyAccess(int id) => 'tracker_$id.access';
  String _keyRefresh(int id) => 'tracker_$id.refresh';
  String _keyUserdata(int id) => 'tracker_$id.userdata';
}

class TrackerCredential {
  const TrackerCredential({
    required this.accessToken,
    this.refreshToken,
    this.userdata,
  });

  final String accessToken;
  final String? refreshToken;
  final String? userdata;
}
