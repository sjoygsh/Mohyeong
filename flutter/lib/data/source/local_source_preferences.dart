/// Stores the root directory/tree the Local source walks to discover manga.
///
/// Two keys are involved:
///
///  * `__APP_STATE_storage_dir` — the canonical key, identical to Mihon's
///    `StoragePreferences.baseStorageDirectory`. On Android this holds a
///    persisted SAF tree URI (`content://…`); on desktop it may hold a
///    plain filesystem path. App-state prefs are excluded from backups,
///    matching Mihon's `appStateKey()` convention.
///
///  * `pref_local_source_root` — the legacy key the first Flutter cut used
///    (always a filesystem path). Read as a fallback so an in-place upgrade
///    keeps working, but never written anymore.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSourcePreferences {
  LocalSourcePreferences(this._prefs);

  /// Canonical key, shared verbatim with Mihon (`appStateKey("storage_dir")`).
  static const String _storageDirKey = '__APP_STATE_storage_dir';

  /// Legacy first-cut key — read-only fallback for upgrades.
  static const String _legacyRootKey = 'pref_local_source_root';

  final SharedPreferences _prefs;

  /// The configured storage root: a `content://` tree URI on Android, or a
  /// filesystem path on desktop. Falls back to the legacy key, then null.
  String? get root {
    final v = _prefs.getString(_storageDirKey);
    if (v != null && v.isNotEmpty) return v;
    final legacy = _prefs.getString(_legacyRootKey);
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return null;
  }

  bool get isSet => root != null;

  Future<void> setRoot(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_storageDirKey);
    } else {
      await _prefs.setString(_storageDirKey, value);
    }
  }
}

/// Lazy loader matching the pattern used elsewhere — no main() override
/// required.
final localSourcePreferencesProvider =
    FutureProvider<LocalSourcePreferences>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return LocalSourcePreferences(prefs);
});

/// Reactive view of the storage-root string for the onboarding Storage step
/// and the Data & storage settings screen. Holds the raw value
/// (`content://…` or a path); null when unset. Writing through [set] keeps
/// SharedPreferences and any watchers in sync.
class StorageDirNotifier extends Notifier<String?> {
  static const String _key = '__APP_STATE_storage_dir';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final value = (stored != null && stored.isNotEmpty) ? stored : null;
    if (value != state) state = value;
  }

  Future<void> set(String? value) async {
    state = (value != null && value.isNotEmpty) ? value : null;
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, state!);
    }
  }

  bool get isSet => state != null;
}

final storageDirProvider =
    NotifierProvider<StorageDirNotifier, String?>(StorageDirNotifier.new);
