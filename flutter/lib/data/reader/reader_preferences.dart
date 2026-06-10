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

/// Reader background. Mirrors Mihon's `pref_reader_theme_key` int pref —
/// stored values match Mihon verbatim (0=White, 1=Black, 2=Gray,
/// 3=Automatic) so imported settings carry across without translation.
/// Gray is Mihon's `grayBackgroundColor` (0xFF202125); Automatic follows
/// the app theme (gray in dark mode, white otherwise — Mihon's
/// `automaticBackgroundColor()`).
enum ReaderBackground {
  white(0, 'White', Colors.white, Colors.black),
  black(1, 'Black', Colors.black, Colors.white),
  gray(2, 'Gray', Color(0xFF202125), Colors.white),
  automatic(3, 'Auto', Colors.white, Colors.black);

  const ReaderBackground(this.flagValue, this.label, this._color, this._onColor);

  final int flagValue;
  final String label;
  final Color _color;
  final Color _onColor;

  /// The order Mihon's settings picker lists the entries in
  /// (Black / Gray / White / Auto).
  static const pickerOrder = <ReaderBackground>[black, gray, white, automatic];

  /// Background colour for the given app-theme [brightness]. [automatic]
  /// resolves like Mihon: gray in dark mode, white otherwise.
  Color resolveColor(Brightness brightness) {
    if (this == ReaderBackground.automatic) {
      return brightness == Brightness.dark
          ? ReaderBackground.gray._color
          : Colors.white;
    }
    return _color;
  }

  /// Foreground colour the reader chrome should switch to so labels
  /// stay legible against [resolveColor].
  Color resolveOnColor(Brightness brightness) {
    if (this == ReaderBackground.automatic) {
      return brightness == Brightness.dark ? Colors.white : Colors.black;
    }
    return _onColor;
  }

  static ReaderBackground fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderBackground.black;
  }
}

/// Reader colour-filter blend mode. Mirrors Mihon's `color_filter_mode`
/// int pref (ordinals match `ReaderPreferences.ColorFilterMode`): the
/// full ARGB [readerColorFilterValueProvider] colour is composited over
/// the page art with the chosen [blendMode].
enum ReaderColorFilterMode {
  none(0, 'Default', BlendMode.srcOver),
  multiply(1, 'Multiply', BlendMode.multiply),
  screen(2, 'Screen', BlendMode.screen),
  overlay(3, 'Overlay', BlendMode.overlay),
  lighten(4, 'Lighten', BlendMode.lighten),
  darken(5, 'Darken', BlendMode.darken);

  const ReaderColorFilterMode(this.flagValue, this.label, this.blendMode);

  final int flagValue;
  final String label;

  /// Dart [BlendMode] the overlay colour is painted with. Mirrors the
  /// `BlendMode` Mihon pairs with each ordinal (SrcOver / Modulate /
  /// Screen / Overlay / Lighten / Darken). We use [BlendMode.multiply]
  /// for Mihon's `Modulate` — Flutter has no Modulate constant and
  /// multiply is the closest perceptual match.
  final BlendMode blendMode;

  static ReaderColorFilterMode fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderColorFilterMode.none;
  }
}

/// Flash colour for the E-Ink page-change flash. Mirrors Mihon's
/// `ReaderPreferences.FlashColor` enum (ordinals 0/1/2, persisted by
/// name via Mihon's `getEnum`). [whiteBlack] alternates white then black
/// across the two halves of the flash.
enum ReaderFlashColor {
  black(0, 'BLACK', 'Black'),
  white(1, 'WHITE', 'White'),
  whiteBlack(2, 'WHITE_BLACK', 'White and Black');

  const ReaderFlashColor(this.flagValue, this.storeName, this.label);

  final int flagValue;

  /// The verbatim enum-constant name Mihon persists (it stores the enum
  /// via `getEnum`, which writes the constant's `name`). Keeping this
  /// exact lets a settings import carry across.
  final String storeName;
  final String label;

  static ReaderFlashColor fromName(String? name) {
    for (final v in values) {
      if (v.storeName == name) return v;
    }
    return ReaderFlashColor.black;
  }
}

/// Tap-zone navigation preset. Mirrors Mihon's `ReaderPreferences.TapZones`
/// list (index == stored int). Each preset maps a normalised tap point to
/// a [NavRegion] via [regionAt], porting Mihon's `ViewerNavigation`
/// rectangle layouts.
enum ReaderNavMode {
  defaultMode(0, 'Default'),
  lShaped(1, 'L shaped'),
  kindlish(2, 'Kindle-ish'),
  edge(3, 'Edge'),
  rightAndLeft(4, 'Right and Left'),
  disabled(5, 'Disabled');

  const ReaderNavMode(this.flagValue, this.label);

  final int flagValue;
  final String label;

  static ReaderNavMode fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderNavMode.defaultMode;
  }
}

/// Logical tap-zone region. [prev]/[next] step a page regardless of
/// reading direction; [left]/[right] are direction-relative (used by the
/// Right-and-Left preset). [menu] toggles the reader chrome.
enum NavRegion { menu, prev, next, left, right }

/// Resolves which [NavRegion] a normalised tap at ([x], [y]) (both 0..1)
/// falls into for [mode]. [horizontal] selects the pager "Default" layout
/// (Right-and-Left for horizontal pagers, L-shaped for vertical/webtoon),
/// mirroring Mihon's `PagerConfig`/`WebtoonConfig` `defaultNavigation()`.
/// Ports the rectangles from Mihon's `viewer/navigation/*Navigation.kt`.
NavRegion navRegionAt(
  ReaderNavMode mode,
  double x,
  double y, {
  required bool horizontal,
}) {
  switch (mode) {
    case ReaderNavMode.disabled:
      return NavRegion.menu;
    case ReaderNavMode.defaultMode:
      return horizontal
          ? _rightAndLeftRegion(x, y)
          : _lNavRegion(x, y);
    case ReaderNavMode.lShaped:
      return _lNavRegion(x, y);
    case ReaderNavMode.kindlish:
      return _kindlishRegion(x, y);
    case ReaderNavMode.edge:
      return _edgeRegion(x, y);
    case ReaderNavMode.rightAndLeft:
      return _rightAndLeftRegion(x, y);
  }
}

// LNavigation: top third = PREV, bottom third = NEXT, middle band split
// left=PREV / centre=MENU / right=NEXT.
NavRegion _lNavRegion(double x, double y) {
  if (y < 0.33) return NavRegion.prev;
  if (y >= 0.66) return NavRegion.next;
  if (x < 0.33) return NavRegion.prev;
  if (x >= 0.66) return NavRegion.next;
  return NavRegion.menu;
}

// KindlishNavigation: top band = MENU, left column (below top) = PREV,
// the rest = NEXT.
NavRegion _kindlishRegion(double x, double y) {
  if (y < 0.33) return NavRegion.menu;
  if (x < 0.33) return NavRegion.prev;
  return NavRegion.next;
}

// EdgeNavigation: left & right columns = NEXT, centre column bottom third
// = PREV, centre otherwise = MENU.
NavRegion _edgeRegion(double x, double y) {
  if (x < 0.33 || x >= 0.66) return NavRegion.next;
  if (y >= 0.66) return NavRegion.prev;
  return NavRegion.menu;
}

// RightAndLeftNavigation: left column = LEFT, right column = RIGHT,
// centre column = MENU.
NavRegion _rightAndLeftRegion(double x, double y) {
  if (x < 0.33) return NavRegion.left;
  if (x >= 0.66) return NavRegion.right;
  return NavRegion.menu;
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

  /// Width/position of the orientation bitfield within `mangas.viewer`
  /// (bits 3..5 — Mihon `ReaderOrientation.MASK = 0x38`).
  static const int mask = 0x38;

  /// The per-manga orientation override stored in `viewerFlags`, or
  /// `null` when the manga inherits the global default (bits == 0,
  /// Mihon's `DEFAULT`).
  static ReaderOrientation? fromMangaFlags(int? viewerFlags) {
    if (viewerFlags == null) return null;
    final bits = viewerFlags & mask;
    if (bits == 0) return null;
    for (final v in values) {
      if (v.flagValue == bits) return v;
    }
    return null;
  }

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
  // Matches Mihon's `pref_reader_theme_key` (default 1 = Black) so
  // settings imports carry through without remapping.
  static const _key = 'pref_reader_theme_key';

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

/// Master enable for the full-colour filter. Mirrors Mihon's
/// `pref_color_filter_key` bool.
class ReaderColorFilterEnabledNotifier extends Notifier<bool> {
  static const _key = 'pref_color_filter_key';

  @override
  bool build() {
    _loadFromDisk();
    return false;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_key);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => set(!state);
}

final readerColorFilterEnabledProvider =
    NotifierProvider<ReaderColorFilterEnabledNotifier, bool>(
  ReaderColorFilterEnabledNotifier.new,
);

/// Full ARGB colour-filter value. Mirrors Mihon's `color_filter_value`
/// int (a packed 0xAARRGGBB stored as a signed int). `0` (fully
/// transparent) means no tint even when the filter is enabled.
class ReaderColorFilterValueNotifier extends Notifier<int> {
  static const _key = 'color_filter_value';

  @override
  int build() {
    _loadFromDisk();
    return 0;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(int argb) async {
    state = argb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, argb);
  }

  /// The overlay [Color] for the stored ARGB int, or `null` when the
  /// value is fully transparent (no visible tint).
  Color? get color {
    if (state == 0) return null;
    // Mihon stores the value as a signed int; mask to 32 bits so a
    // negative (high-alpha) value reconstructs the right ARGB.
    return Color(state & 0xFFFFFFFF);
  }
}

final readerColorFilterValueProvider =
    NotifierProvider<ReaderColorFilterValueNotifier, int>(
  ReaderColorFilterValueNotifier.new,
);

/// Colour-filter blend mode. Mirrors Mihon's `color_filter_mode` int.
class ReaderColorFilterModeNotifier extends Notifier<ReaderColorFilterMode> {
  static const _key = 'color_filter_mode';

  @override
  ReaderColorFilterMode build() {
    _loadFromDisk();
    return ReaderColorFilterMode.none;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderColorFilterMode.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderColorFilterMode value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerColorFilterModeProvider =
    NotifierProvider<ReaderColorFilterModeNotifier, ReaderColorFilterMode>(
  ReaderColorFilterModeNotifier.new,
);

/// Image scale type for the paged readers. Mirrors Mihon's
/// `pref_image_scale_type_key` int (ordinals 1..6; default 1 = fit
/// screen). Stored as an int — distinct from the legacy string-based
/// `readerScaleTypeProvider` so imports carry across verbatim.
enum ReaderImageScaleType {
  fitScreen(1, 'Fit screen', BoxFit.contain),
  stretch(2, 'Stretch', BoxFit.fill),
  fitWidth(3, 'Fit width', BoxFit.fitWidth),
  fitHeight(4, 'Fit height', BoxFit.fitHeight),
  originalSize(5, 'Original size', BoxFit.none),
  smartFit(6, 'Smart fit', BoxFit.contain);

  const ReaderImageScaleType(this.flagValue, this.label, this.boxFit);

  final int flagValue;
  final String label;

  /// [BoxFit] applied to each page. Mihon's "Smart fit" picks fit-width
  /// or fit-height per page based on aspect ratio; without that runtime
  /// decision we fall back to [BoxFit.contain] (parent can device-verify).
  final BoxFit boxFit;

  static ReaderImageScaleType fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderImageScaleType.fitScreen;
  }
}

class ReaderImageScaleTypeNotifier extends Notifier<ReaderImageScaleType> {
  static const _key = 'pref_image_scale_type_key';

  @override
  ReaderImageScaleType build() {
    _loadFromDisk();
    return ReaderImageScaleType.fitScreen;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderImageScaleType.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderImageScaleType value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerImageScaleTypeProvider =
    NotifierProvider<ReaderImageScaleTypeNotifier, ReaderImageScaleType>(
  ReaderImageScaleTypeNotifier.new,
);

/// Zoom start position for the paged readers. Mirrors Mihon's
/// `pref_zoom_start_key` int (1=automatic, 2=left, 3=right, 4=centre;
/// default 1).
enum ReaderZoomStart {
  automatic(1, 'Automatic'),
  left(2, 'Left'),
  right(3, 'Right'),
  center(4, 'Center');

  const ReaderZoomStart(this.flagValue, this.label);

  final int flagValue;
  final String label;

  static ReaderZoomStart fromFlag(int? flag) {
    for (final v in values) {
      if (v.flagValue == flag) return v;
    }
    return ReaderZoomStart.automatic;
  }
}

class ReaderZoomStartNotifier extends Notifier<ReaderZoomStart> {
  static const _key = 'pref_zoom_start_key';

  @override
  ReaderZoomStart build() {
    _loadFromDisk();
    return ReaderZoomStart.automatic;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderZoomStart.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderZoomStart value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerZoomStartProvider =
    NotifierProvider<ReaderZoomStartNotifier, ReaderZoomStart>(
  ReaderZoomStartNotifier.new,
);

/// E-Ink flash colour. Mirrors Mihon's `pref_reader_flash_mode` enum
/// pref (persisted by the constant's name).
class ReaderFlashColorNotifier extends Notifier<ReaderFlashColor> {
  static const _key = 'pref_reader_flash_mode';

  @override
  ReaderFlashColor build() {
    _loadFromDisk();
    return ReaderFlashColor.black;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    final loaded = ReaderFlashColor.fromName(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderFlashColor value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.storeName);
  }
}

final readerFlashColorProvider =
    NotifierProvider<ReaderFlashColorNotifier, ReaderFlashColor>(
  ReaderFlashColorNotifier.new,
);

/// Tap-zone navigation preset for the paged (pager) readers. Mirrors
/// Mihon's `reader_navigation_mode_pager` int.
class ReaderNavModePagerNotifier extends Notifier<ReaderNavMode> {
  static const _key = 'reader_navigation_mode_pager';

  @override
  ReaderNavMode build() {
    _loadFromDisk();
    return ReaderNavMode.defaultMode;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderNavMode.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderNavMode value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerNavModePagerProvider =
    NotifierProvider<ReaderNavModePagerNotifier, ReaderNavMode>(
  ReaderNavModePagerNotifier.new,
);

/// Tap-zone navigation preset for the continuous (webtoon) reader.
/// Mirrors Mihon's `reader_navigation_mode_webtoon` int.
class ReaderNavModeWebtoonNotifier extends Notifier<ReaderNavMode> {
  static const _key = 'reader_navigation_mode_webtoon';

  @override
  ReaderNavMode build() {
    _loadFromDisk();
    return ReaderNavMode.defaultMode;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    final loaded = ReaderNavMode.fromFlag(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> set(ReaderNavMode value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.flagValue);
  }
}

final readerNavModeWebtoonProvider =
    NotifierProvider<ReaderNavModeWebtoonNotifier, ReaderNavMode>(
  ReaderNavModeWebtoonNotifier.new,
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

/// Resolves the effective reader orientation for a given per-manga
/// `viewerFlags` (bits 3..5). Returns the per-manga override when set;
/// falls back to the user's global default otherwise — mirrors Mihon's
/// `ReaderOrientation.fromPreference` + `defaultOrientationType` chain.
ReaderOrientation resolveReaderOrientation(
  int? viewerFlags,
  ReaderOrientation globalDefault,
) =>
    ReaderOrientation.fromMangaFlags(viewerFlags) ?? globalDefault;
