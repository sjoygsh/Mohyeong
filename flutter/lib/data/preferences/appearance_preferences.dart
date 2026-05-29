/// Appearance preferences exposed under Settings → Appearance, beyond the
/// core theme-mode toggle (which lives in `theme_preference.dart`). Keys
/// mirror the Kotlin app where one exists so a settings import carries
/// across.
///
/// Only [amoledProvider] is consumed today — `main.dart` swaps in a
/// pure-black dark theme when it's on. The rest are persisted and shown
/// in the settings UI but not yet behaviourally wired (date/relative-time
/// formatting is done ad-hoc at each call site; tablet mode and app
/// language need layout/localisation work that isn't built).
library;

import 'typed_preferences.dart';

/// Use a pure-black background for the dark theme (OLED power saving).
final amoledProvider = boolPref('pref_theme_dark_amoled', false);

/// Show timestamps as "2h ago" style relative times instead of absolute
/// dates. Stored-only for now.
final relativeTimestampsProvider = boolPref('relative_time_v2', true);

/// Absolute date display pattern (e.g. "yyyy-MM-dd"). Stored-only.
final dateFormatProvider = stringPref('app_date_format', 'yyyy-MM-dd');

/// Force the tablet (two-pane) layout regardless of screen width.
/// Stored-only — the responsive layouts aren't built.
final tabletUiModeProvider = boolPref('pref_tablet_ui_mode', false);

/// Render images embedded in manga descriptions. Stored-only.
final showImagesInDescriptionProvider =
    boolPref('pref_show_images_in_description', true);
