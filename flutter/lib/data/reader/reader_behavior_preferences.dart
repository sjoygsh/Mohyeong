/// Reader behaviour toggles that Mihon exposes under Settings → Reader.
/// These are simple scalar prefs declared via the shared
/// [typed_preferences] helpers. Keys mirror the Kotlin `ReaderPreferences`
/// names so a settings import carries values across without translation.
library;

import '../preferences/typed_preferences.dart';

/// Show the "current / total" page-number indicator in the reader chrome.
final readerShowPageNumberProvider = boolPref('pref_show_page_number_key', true);

/// Briefly flash the active reading-mode label when a chapter opens.
final readerShowReadingModeProvider = boolPref('pref_show_reading_mode', true);

/// Hide the system status/navigation bars while reading.
final readerFullscreenProvider = boolPref('pref_fullscreen_key', true);

/// Animate page changes in the paged readers (slide transition).
final readerPageTransitionsProvider = boolPref('pref_enable_transitions', true);

/// Keep the device awake while the reader is open. Honoured by the reader
/// screen via the `wakelock_plus` plugin.
final readerKeepScreenOnProvider = boolPref('pref_keep_screen_on', true);

/// When advancing past the end of a chapter, skip chapters that are
/// already marked read instead of opening them. Key matches Mihon's
/// `skip_read` verbatim for settings-import compatibility.
final readerSkipReadProvider = boolPref('skip_read', false);

/// Skip chapters hidden by the manga's active chapter filters when
/// navigating between chapters. Mihon key `skip_filtered`.
final readerSkipFilteredProvider = boolPref('skip_filtered', true);

/// Skip chapters that duplicate the chapter number of an adjacent one
/// (e.g. multiple scanlations of the same chapter) when navigating.
/// Mihon key `skip_dupe`.
final readerSkipDupeProvider = boolPref('skip_dupe', false);

/// Always interpose the chapter-transition screen between chapters, even
/// when the next chapter is immediately available. Mihon key
/// `always_show_chapter_transition`.
final readerAlwaysShowTransitionProvider =
    boolPref('always_show_chapter_transition', true);

/// Long-press a page to open the page actions sheet (share/save/set as
/// cover). Mihon key `reader_long_tap`, default on.
final readerLongTapProvider = boolPref('reader_long_tap', true);

/// E-Ink: briefly paint a full-screen flash on page change to clear
/// ghosting. Mihon key `pref_reader_flash`.
final readerFlashOnPageChangeProvider =
    boolPref('pref_reader_flash', false);

/// E-Ink flash duration in milliseconds. Mihon stores raw ms with a
/// `MILLI_CONVERSION` of 100 (slider range 1..15 → 100..1500ms); default
/// 100. Key `pref_reader_flash_duration`.
final readerFlashDurationProvider =
    intPref('pref_reader_flash_duration', 100);

/// E-Ink flash interval in pages — flash every Nth page change. Mihon key
/// `pref_reader_flash_interval`, range 1..10, default 1.
final readerFlashIntervalProvider =
    intPref('pref_reader_flash_interval', 1);

/// Double-tap zoom animation duration in milliseconds. Mihon presets are
/// 0 (instant) / 250 / 500.
final readerDoubleTapAnimSpeedProvider =
    intPref('pref_double_tap_anim_speed', 500);

/// Render pages in greyscale (desaturate the page art).
final readerGrayscaleProvider = boolPref('pref_grayscale', false);

/// Invert page colours (negative). Useful for dark-on-light scans.
final readerInvertedColorsProvider = boolPref('pref_inverted_colors', false);

/// Override the screen brightness while reading. Honoured by the reader
/// screen via the `screen_brightness` plugin — when on, the reader applies
/// [readerBrightnessValueProvider] on open and restores the system
/// brightness on close.
final readerCustomBrightnessProvider =
    boolPref('pref_custom_brightness', false);

/// Reader brightness level when [readerCustomBrightnessProvider] is on,
/// expressed 1..100 (percent of full brightness). Mihon stores a
/// -75..100 range where negatives dim via an overlay; we keep it simple
/// and only drive the hardware brightness in the positive range.
final readerBrightnessValueProvider =
    intPref('pref_custom_brightness_value', 50);

// Image scale type now lives in reader_preferences.dart as the
// int-backed `readerImageScaleTypeProvider` (Mihon key
// `pref_image_scale_type_key`), replacing the earlier string-keyed pref.

/// Horizontal padding (percent of viewport width, 0..25) applied to each
/// page in the continuous webtoon scroll. 0 = edge-to-edge.
final readerWebtoonSidePaddingProvider =
    intPref('webtoon_side_padding', 0);

/// Crop solid borders off page images on display. Honoured by the reader:
/// when on, each page is routed through `CropBordersImageProvider`, which
/// samples the page corners for the background colour and trims uniform
/// margins before the image is painted.
final readerCropBordersProvider = boolPref('crop_borders', false);

/// Allow zooming wide (landscape) pages beyond fit. Stored-only — the
/// paged viewer's InteractiveViewer already permits free zoom.
final readerLandscapeZoomProvider = boolPref('landscape_zoom', false);

/// Tap the left/right thirds of the screen to turn pages in the paged
/// readers. When off, a tap anywhere just toggles the reader chrome.
final readerTapToNavigateProvider = boolPref('pref_tap_navigation', true);

/// Swap the left/right tap zones (left = forward, right = back).
final readerTapNavigateInvertProvider =
    boolPref('pref_tap_navigation_invert', false);

/// Use the hardware volume keys to turn pages (paged modes) or scroll
/// (continuous modes). Wired through the native `app.mohyeong/volume_keys`
/// channel — see `ReaderVolumeKeys`. Interception is active only while the
/// reader is open and its chrome is hidden, mirroring Mihon (volume keys
/// keep their normal function whenever the reader menu is visible).
final readerVolumeKeysProvider = boolPref('reader_volume_keys', false);

/// Swap the volume-key direction (volume-up advances, volume-down goes
/// back). Mirrors Mihon's `reader_volume_keys_inverted`.
final readerVolumeKeysInvertedProvider =
    boolPref('reader_volume_keys_inverted', false);

/// Show the one-time tap-zone guide overlay the first time a paged chapter
/// is opened (Mihon's "new user" navigation hint). The reader paints
/// `_NavZoneOverlay` while this is true and flips it off when the user taps
/// the overlay away.
final readerShowNavOverlayProvider =
    boolPref('pref_show_navigation_overlay_new_user', true);
