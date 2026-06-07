/// Sync configuration: which service the user picked, the host/url, the
/// secret material (api key / password / OAuth access token), and a few
/// "what to include" flags.
///
/// Secrets live in [FlutterSecureStorage] (platform keystore/keychain)
/// while non-secret config lives in SharedPreferences alongside the rest
/// of the app's preferences. We mirror Mihon's `SyncPreferences` keys so
/// a future migration can lift them over verbatim.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which sync backend is currently configured. Ordinal matches Mihon's
/// `SyncService` enum on disk so a backup-imported pref reads the right
/// service.
enum SyncService {
  none,
  syncYomi,
  webDav,
  googleDrive,
  dropbox;

  int get dbValue => index;

  static SyncService fromInt(int value) {
    if (value < 0 || value >= SyncService.values.length) {
      return SyncService.none;
    }
    return SyncService.values[value];
  }

  // Labels match Kotlin SettingsSyncScreen's sync_service_* strings verbatim.
  String get label => switch (this) {
        SyncService.none => 'Disabled',
        SyncService.syncYomi => 'SyncYomi-compatible server',
        SyncService.webDav => 'WebDAV',
        SyncService.googleDrive => 'Google Drive',
        SyncService.dropbox => 'Dropbox',
      };
}

/// Stable on-disk preference keys. Anything ending in `_secret` is held
/// in secure storage, NOT SharedPreferences.
class _Keys {
  static const service = 'pref_sync_service';
  static const host = 'pref_sync_host';
  static const username = 'pref_sync_username';
  static const deviceId = 'pref_sync_device_id';
  static const lastSyncTimestamp = 'pref_sync_last_timestamp';
  static const syncCategories = 'pref_sync_categories';
  static const syncChapters = 'pref_sync_chapters';
  static const syncTracking = 'pref_sync_tracking';
  static const syncHistory = 'pref_sync_history';

  // Automation (Kotlin SyncPreferences.autoSync*/syncOnAppStart). Kept in the
  // file's own `pref_sync_*` namespace for internal consistency — sync config
  // is device-local and not part of the cross-app settings-import surface.
  static const autoSyncEnabled = 'pref_sync_auto_enabled';
  static const autoSyncIntervalHours = 'pref_sync_auto_interval_hours';
  static const syncOnAppStart = 'pref_sync_on_app_start';

  // Secure-storage keys.
  static const apiKeySecret = 'sync_api_key';
}

class SyncPreferencesData {
  const SyncPreferencesData({
    required this.service,
    required this.host,
    required this.username,
    required this.deviceId,
    required this.lastSyncTimestamp,
    required this.syncCategories,
    required this.syncChapters,
    required this.syncTracking,
    required this.syncHistory,
    required this.autoSyncEnabled,
    required this.autoSyncIntervalHours,
    required this.syncOnAppStart,
  });

  final SyncService service;
  final String host;
  final String username;
  final String deviceId;
  final int lastSyncTimestamp;
  final bool syncCategories;
  final bool syncChapters;
  final bool syncTracking;
  final bool syncHistory;
  final bool autoSyncEnabled;
  final int autoSyncIntervalHours;
  final bool syncOnAppStart;

  SyncPreferencesData copyWith({
    SyncService? service,
    String? host,
    String? username,
    String? deviceId,
    int? lastSyncTimestamp,
    bool? syncCategories,
    bool? syncChapters,
    bool? syncTracking,
    bool? syncHistory,
    bool? autoSyncEnabled,
    int? autoSyncIntervalHours,
    bool? syncOnAppStart,
  }) {
    return SyncPreferencesData(
      service: service ?? this.service,
      host: host ?? this.host,
      username: username ?? this.username,
      deviceId: deviceId ?? this.deviceId,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      syncCategories: syncCategories ?? this.syncCategories,
      syncChapters: syncChapters ?? this.syncChapters,
      syncTracking: syncTracking ?? this.syncTracking,
      syncHistory: syncHistory ?? this.syncHistory,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      autoSyncIntervalHours:
          autoSyncIntervalHours ?? this.autoSyncIntervalHours,
      syncOnAppStart: syncOnAppStart ?? this.syncOnAppStart,
    );
  }
}

class SyncPreferences {
  SyncPreferences({
    required SharedPreferences prefs,
    FlutterSecureStorage? secureStorage,
  })  :
        // ignore: prefer_initializing_formals
        _prefs = prefs,
        _secure = secureStorage ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  SyncPreferencesData read() {
    return SyncPreferencesData(
      service:
          SyncService.fromInt(_prefs.getInt(_Keys.service) ?? 0),
      host: _prefs.getString(_Keys.host) ?? '',
      username: _prefs.getString(_Keys.username) ?? '',
      deviceId: _prefs.getString(_Keys.deviceId) ?? '',
      lastSyncTimestamp: _prefs.getInt(_Keys.lastSyncTimestamp) ?? 0,
      syncCategories: _prefs.getBool(_Keys.syncCategories) ?? true,
      syncChapters: _prefs.getBool(_Keys.syncChapters) ?? true,
      syncTracking: _prefs.getBool(_Keys.syncTracking) ?? true,
      syncHistory: _prefs.getBool(_Keys.syncHistory) ?? true,
      autoSyncEnabled: _prefs.getBool(_Keys.autoSyncEnabled) ?? false,
      autoSyncIntervalHours:
          _prefs.getInt(_Keys.autoSyncIntervalHours) ?? 12,
      syncOnAppStart: _prefs.getBool(_Keys.syncOnAppStart) ?? false,
    );
  }

  Future<void> write(SyncPreferencesData data) async {
    await _prefs.setInt(_Keys.service, data.service.dbValue);
    await _prefs.setString(_Keys.host, data.host);
    await _prefs.setString(_Keys.username, data.username);
    await _prefs.setString(_Keys.deviceId, data.deviceId);
    await _prefs.setInt(_Keys.lastSyncTimestamp, data.lastSyncTimestamp);
    await _prefs.setBool(_Keys.syncCategories, data.syncCategories);
    await _prefs.setBool(_Keys.syncChapters, data.syncChapters);
    await _prefs.setBool(_Keys.syncTracking, data.syncTracking);
    await _prefs.setBool(_Keys.syncHistory, data.syncHistory);
    await _prefs.setBool(_Keys.autoSyncEnabled, data.autoSyncEnabled);
    await _prefs.setInt(
        _Keys.autoSyncIntervalHours, data.autoSyncIntervalHours);
    await _prefs.setBool(_Keys.syncOnAppStart, data.syncOnAppStart);
  }

  Future<String> getApiKey() async {
    return (await _secure.read(key: _Keys.apiKeySecret)) ?? '';
  }

  Future<void> setApiKey(String value) async {
    if (value.isEmpty) {
      await _secure.delete(key: _Keys.apiKeySecret);
    } else {
      await _secure.write(key: _Keys.apiKeySecret, value: value);
    }
  }

  Future<void> setLastSyncTimestamp(int ms) async {
    await _prefs.setInt(_Keys.lastSyncTimestamp, ms);
  }
}

/// Loads SharedPreferences lazily — matches the pattern in
/// `theme_preference.dart` and avoids forcing every entry point to
/// pre-init the provider override.
final syncPreferencesProvider = FutureProvider<SyncPreferences>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SyncPreferences(prefs: prefs);
});
