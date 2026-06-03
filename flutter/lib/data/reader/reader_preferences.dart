/// Global reader preferences. Exposes the default reading mode plus
/// the visual prefs (background colour, colour filter) that ride
/// alongside it. Structured the same way as
/// `library_update_preference.dart` so future settings (page
/// transitions, etc.) drop in without disrupting callers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/reader/model/reading_mode.dart';

/// Reader background. Mirrors Mihon's `reader_color_value` int pref —
/// values chosen to match Mihon's `ReaderBackgroundColor` ordinals so
/// imported settings carry across without translation.
enum ReaderBackground {
  black(0, 'Black', Colors.black, Colors.white),
  gray(1, 'Grey', Color(0xFF1E1E1E), Colors.white),
  white(2, 'White', Colors.white, Colors.black);

  const ReaderBackground(this.flagValue, this.label, this.color, this.onColor);

  final int flagValue;
  final String label;
  final Color color;

  /// Foreground colour the reader chrome should switch to so labels
  /// stay legible against [color].
  final Color onColor;

  static ReaderBackground fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderBackground.black;
  }
}

/// Reader colour filter. Mirrors Mihon's reader-tint feature — applied
/// as a translucent overlay over the page viewport.
enum ReaderColorFilter {
  none(0, 'None', null),
  sepia(1, 'Sepia', Color(0x33704214)),
  yellow(2, 'Yellow', Color(0x33FFEB3B)),
  blue(3, 'Blue', Color(0x332962FF));

  const ReaderColorFilter(this.flagValue, this.label, this.overlay);

  final int flagValue;
  final String label;

  /// `null` for [none]; otherwise the translucent colour painted on top
  /// of pages. Reader uses `BlendMode.srcOver` (default) so a low alpha
  /// preserves the underlying art.
  final Color? overlay;

  static ReaderColorFilter fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderColorFilter.none;
  }
}

/// Reader screen-orientation lock. Mirrors Mihon's `ReaderOrientation`
/// enum — [flagValue] matches Mihon's ordinals so an imported
/// `pref_default_orientation_type_key` carries across without
/// translation. [DEFAULT]/[FREE] leave rotation to the device sensor;
/// the rest pin the reader to a fixed (or sensor-constrained) axis via
/// [orientations] applied with [SystemChrome.setPreferredOrientations].
enum ReaderOrientation {
  free(0x00000008, 'Free'),
  portrait(0x00000010, 'Portrait'),
  landscape(0x00000018, 'Landscape'),
  lockedPortrait(0x00000020, 'Locked portrait'),
  lockedLandscape(0x00000028, 'Locked landscape'),
  reversePortrait(0x00000030, 'Reverse portrait');

  const ReaderOrientation(this.flagValue, this.label);

  final int flagValue;
  final String label;

  /// The device orientations to permit while reading. An empty list
  /// means "no constraint" (let the sensor decide) — matches Android's
  /// `SCREEN_ORIENTATION_UNSPECIFIED` for [free].
  List<DeviceOrientation> get orientations {
    switch (this) {
      case ReaderOrientation.free:
        return const [];
      case ReaderOrientation.portrait:
        return const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
      case ReaderOrientation.landscape:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case ReaderOrientation.lockedPortrait:
        return const [DeviceOrientation.portraitUp];
      case ReaderOrientation.lockedLandscape:
        return const [DeviceOrientation.landscapeLeft];
      case ReaderOrientation.reversePortrait:
        return const [DeviceOrientation.portraitDown];
    }
  }

  static ReaderOrientation fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderOrientation.free;
  }
}

class ReaderOrientationNotifier extends Notifier<ReaderOrientation> {
  // Mirrors Mihon's `pref_default_orientation_type_key`, dropping the
  // `pref_`/`_key` affixes to match the rest of the Flutter prefs.
  static const _key = 'default_orientation_type';

  @override
  ReaderOrientation build() {
    _loadFromDisk();
    return ReaderOrientation.free;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderOrientation.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderOrientation value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerOrientationProvider =
    NotifierProvider<ReaderOrientationNotifier, ReaderOrientation>(
  ReaderOrientationNotifier.new,
);

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

class ReaderBackgroundNotifier extends Notifier<ReaderBackground> {
  // Matches Mihon's `reader_color_value` key so settings imports carry
  // through without remapping.
  static const _key = 'reader_color_value';

  @override
  ReaderBackground build() {
    _loadFromDisk();
    return ReaderBackground.black;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderBackground.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderBackground value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerBackgroundProvider =
    NotifierProvider<ReaderBackgroundNotifier, ReaderBackground>(
  ReaderBackgroundNotifier.new,
);

class ReaderColorFilterNotifier extends Notifier<ReaderColorFilter> {
  static const _key = 'reader_color_filter';

  @override
  ReaderColorFilter build() {
    _loadFromDisk();
    return ReaderColorFilter.none;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderColorFilter.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderColorFilter value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerColorFilterProvider =
    NotifierProvider<ReaderColorFilterNotifier, ReaderColorFilter>(
  ReaderColorFilterNotifier.new,
);

/// Auto-hide delay for the reader's top/bottom chrome (header + page
/// indicator strip). `0` keeps the chrome pinned until the user taps
/// the viewport again — matches the previous behaviour. Any positive
/// value re-arms a timer whenever the chrome becomes visible so it
/// fades back out after [state] seconds. Mihon's equivalent is the
/// `pref_keep_screen_on` companion pref `pref_reader_hide_threshold`
/// (we drop the `pref_` prefix to fit the rest of the Flutter prefs).
class ReaderAutoHideChromeNotifier extends Notifier<int> {
  static const _key = 'reader_auto_hide_chrome_seconds';
  static const _default = 0;

  /// Presets surfaced by the picker. Kept here so the settings screen
  /// and any future quick-access menu agree on the same values.
  static const presets = <int>[0, 3, 5, 10, 30];

  @override
  int build() {
    _loadFromDisk();
    return _default;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    if (stored == null) return;
    // Clamp to the preset set so a stray import can't park us on a
    // bizarre delay (e.g. 1 second, which would feel like the chrome
    // is broken).
    final resolved = presets.contains(stored) ? stored : _default;
    if (resolved != state) state = resolved;
  }

  Future<void> set(int seconds) async {
    state = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, seconds);
  }
}

final readerAutoHideChromeSecondsProvider =
    NotifierProvider<ReaderAutoHideChromeNotifier, int>(
  ReaderAutoHideChromeNotifier.new,
);

/// Resolves the effective reading mode for a given per-manga
/// `viewerFlags`. Returns the per-manga override when set; falls back
/// to the user's global default otherwise.
ReadingMode resolveReadingMode(int? viewerFlags, ReadingMode globalDefault) {
  final perManga = ReadingMode.fromFlag(viewerFlags);
  if (perManga == ReadingMode.defaultMode) return globalDefault;
  return perManga;
}
