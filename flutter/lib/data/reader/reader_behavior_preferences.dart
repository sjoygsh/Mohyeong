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
