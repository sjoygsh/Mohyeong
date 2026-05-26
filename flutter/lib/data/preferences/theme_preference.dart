import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted choice of `ThemeMode`, mirroring the Kotlin app's
/// `themeMode` preference. Stored in SharedPreferences (Android-backed by
/// the same SharedPreferences XML, so future migrations from the Kotlin
/// preference key can read this key directly).
class ThemePreferenceNotifier extends Notifier<ThemeMode> {
  // Key chosen to match the Kotlin Preference key, so a future preference
  // import step can carry the value over without translation.
  static const _key = 'pref_theme_mode';

  @override
  ThemeMode build() {
    // Default until the async load resolves -- system follows the OS.
    _loadFromDisk();
    return ThemeMode.system;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final loaded = _decode(stored);
    if (loaded != state) {
      state = loaded;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(mode));
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemeMode>(
  ThemePreferenceNotifier.new,
);
