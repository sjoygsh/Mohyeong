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

/// Keep the device awake while the reader is open. Requires the wakelock
/// plugin to take effect — the pref is honoured by the reader screen.
final readerKeepScreenOnProvider = boolPref('pref_keep_screen_on', true);

/// When advancing past the end of a chapter, skip chapters that are
/// already marked read instead of opening them.
final readerSkipReadProvider = boolPref('pref_skip_read_chapters', false);

/// Skip chapters hidden by the manga's active chapter filters when
/// navigating between chapters.
final readerSkipFilteredProvider = boolPref('pref_skip_filtered_chapters', true);

/// Skip chapters that duplicate the chapter number of an adjacent one
/// (e.g. multiple scanlations of the same chapter) when navigating.
final readerSkipDupeProvider = boolPref('pref_skip_dupe_chapters', false);

/// Always interpose the chapter-transition screen between chapters, even
/// when the next chapter is immediately available.
final readerAlwaysShowTransitionProvider =
    boolPref('pref_always_show_chapter_transition', true);

/// Double-tap zoom animation duration in milliseconds. Mihon presets are
/// 0 (instant) / 250 / 500.
final readerDoubleTapAnimSpeedProvider =
    intPref('pref_double_tap_anim_speed', 500);

/// Render pages in greyscale (desaturate the page art).
final readerGrayscaleProvider = boolPref('pref_grayscale', false);

/// Invert page colours (negative). Useful for dark-on-light scans.
final readerInvertedColorsProvider = boolPref('pref_inverted_colors', false);

/// Override the screen brightness while reading. Stored-only for now —
/// honouring it needs a screen-brightness plugin which isn't in pubspec.
final readerCustomBrightnessProvider =
    boolPref('pref_custom_brightness', false);

/// How page images are scaled to the viewport. Stored as the
/// [ReaderScaleType.key] string; convert via `ReaderScaleType.fromKey`.
final readerScaleTypeProvider = stringPref('pref_image_scale_type', 'fit_screen');

/// Horizontal padding (percent of viewport width, 0..25) applied to each
/// page in the continuous webtoon scroll. 0 = edge-to-edge.
final readerWebtoonSidePaddingProvider =
    intPref('webtoon_side_padding', 0);

/// Crop solid borders off page images on display. Stored-only — needs an
/// image-analysis pass that isn't built.
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

/// Use the hardware volume keys to turn pages. Stored-only — Android
/// doesn't deliver volume key events to Flutter without a platform
/// channel, which isn't wired.
final readerVolumeKeysProvider = boolPref('reader_volume_keys', false);

/// Show the tap-zone guide overlay when opening a chapter. Stored-only —
/// the guide overlay itself isn't built yet.
final readerShowNavOverlayProvider =
    boolPref('pref_show_navigation_overlay_new_user', true);
