/// Appearance preferences exposed under Settings → Appearance.
///
/// Everything here is READ by something. Three preferences were removed on
/// 2026-07-29 because nothing read them — `pref_app_theme` (the colour-seed
/// picker, which `_tide()` overrode every slot of), `pref_tablet_ui_mode` and
/// `pref_show_images_in_description` (both of whose own subtitles admitted
/// "not yet active"). A switch that stores a value nobody reads is a switch
/// that lies about what it does. If any of them comes back, it comes back
/// with the feature.
///
/// Removing them does not break importing a Mihon backup: the restorer
/// replays SharedPreferences keys generically rather than by name, so an
/// imported `pref_app_theme` still lands in storage — the app simply no
/// longer acts on it.
library;

import 'typed_preferences.dart';

/// Use a pure-black background for the dark theme (OLED power saving).
/// Read by `main.dart`, which swaps in [AppTheme.darkAmoled].
final amoledProvider = boolPref('pref_theme_dark_amoled', false);

/// Show timestamps as "2h ago" style relative times instead of absolute
/// dates. Honoured by the History tab via `formatTimestamp`.
final relativeTimestampsProvider = boolPref('relative_time_v2', true);

/// Absolute date display pattern (e.g. "yyyy-MM-dd"), used by `formatDate`
/// wherever a timestamp is not shown relatively.
final dateFormatProvider = stringPref('app_date_format', 'yyyy-MM-dd');
