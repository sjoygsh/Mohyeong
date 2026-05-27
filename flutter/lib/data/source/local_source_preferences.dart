/// Stores the root directory the Local source walks to discover manga.
///
/// Backed by SharedPreferences under `pref_local_source_root` — the same
/// key Mihon uses, so a future settings-import path can carry the value
/// across without translation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSourcePreferences {
  LocalSourcePreferences(this._prefs);

  static const String _rootKey = 'pref_local_source_root';

  final SharedPreferences _prefs;

  String? get root {
    final v = _prefs.getString(_rootKey);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setRoot(String? path) async {
    if (path == null || path.isEmpty) {
      await _prefs.remove(_rootKey);
    } else {
      await _prefs.setString(_rootKey, path);
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
