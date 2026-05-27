/// Global reader preferences. Currently exposes only the default
/// reading mode, but is structured the same way as
/// `library_update_preference.dart` so future settings (background
/// colour, page transitions, etc.) drop in without disrupting callers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/reader/model/reading_mode.dart';

class ReaderPreferencesNotifier extends Notifier<ReadingMode> {
  // Matches Mihon's `default_reading_mode` int preference so a future
  // settings-import path can carry the value across without translation.
  static const _key = 'default_reading_mode';

  @override
  ReadingMode build() {
    _loadFromDisk();
    return ReadingMode.webtoon;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReadingMode.fromFlag(stored ?? ReadingMode.webtoon.flagValue);
    // Reading "default" globally would mean "no default" — coerce to webtoon
    // so the reader always has a renderable mode to fall back to.
    final resolved =
        loaded == ReadingMode.defaultMode ? ReadingMode.webtoon : loaded;
    if (resolved != state) state = resolved;
  }

  Future<void> setMode(ReadingMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, mode.flagValue);
  }
}

final readerPreferencesProvider =
    NotifierProvider<ReaderPreferencesNotifier, ReadingMode>(
  ReaderPreferencesNotifier.new,
);

/// Resolves the effective reading mode for a given per-manga
/// `viewerFlags`. Returns the per-manga override when set; falls back
/// to the user's global default otherwise.
ReadingMode resolveReadingMode(int? viewerFlags, ReadingMode globalDefault) {
  final perManga = ReadingMode.fromFlag(viewerFlags);
  if (perManga == ReadingMode.defaultMode) return globalDefault;
  return perManga;
}
