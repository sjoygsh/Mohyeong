/// Appearance preferences exposed under Settings → Appearance, beyond the
/// core theme-mode toggle (which lives in `theme_preference.dart`). Keys
/// mirror the Kotlin app where one exists so a settings import carries
/// across.
///
/// [amoledProvider] (dark theme), [relativeTimestampsProvider] and
/// [dateFormatProvider] (History timestamp rendering via `formatTimestamp`)
/// are wired. [tabletUiModeProvider] and [showImagesInDescriptionProvider]
/// stay stored-only — they need responsive-layout / description-rendering
/// work that isn't built.
library;

import 'typed_preferences.dart';

/// App colour palette (Mihon's `AppTheme`). Stored as the Kotlin enum name
/// (e.g. `MIDNIGHT_DUSK`); resolve via `AppColorTheme.fromKey`. Wired into
/// `main.dart`, which seeds the light/dark `ColorScheme` from the choice.
final appThemeProvider = stringPref('pref_app_theme', 'DEFAULT');

/// Use a pure-black background for the dark theme (OLED power saving).
final amoledProvider = boolPref('pref_theme_dark_amoled', false);

/// Show timestamps as "2h ago" style relative times instead of absolute
/// dates. Honoured by the History tab via `formatTimestamp`.
final relativeTimestampsProvider = boolPref('relative_time_v2', true);

/// Absolute date display pattern (e.g. "yyyy-MM-dd"). Stored-only.
final dateFormatProvider = stringPref('app_date_format', 'yyyy-MM-dd');

/// Force the tablet (two-pane) layout regardless of screen width.
/// Stored-only — the responsive layouts aren't built.
final tabletUiModeProvider = boolPref('pref_tablet_ui_mode', false);

/// Render images embedded in manga descriptions. Stored-only.
final showImagesInDescriptionProvider =
    boolPref('pref_show_images_in_description', true);
