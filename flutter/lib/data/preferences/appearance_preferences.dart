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
/// `pref_theme_dark_amoled` joined them on 2026-07-31. It looked wired —
/// main.dart really did swap in a darkAmoled ThemeData — but no Tide widget
/// reads the scheme; every screen paints TideColors.ground directly, so the
/// switch moved zero pixels. Pure black comes back when the ground colour
/// itself can respond to it.
///
/// Removing them does not break importing a Mihon backup: the restorer
/// replays SharedPreferences keys generically rather than by name, so an
/// imported `pref_app_theme` still lands in storage — the app simply no
/// longer acts on it.
library;

import 'typed_preferences.dart';

/// Show timestamps as "2h ago" style relative times instead of absolute
/// dates. Honoured by the History tab via `formatTimestamp`.
final relativeTimestampsProvider = boolPref('relative_time_v2', true);

/// Absolute date display pattern (e.g. "yyyy-MM-dd"), used by `formatDate`
/// wherever a timestamp is not shown relatively.
final dateFormatProvider = stringPref('app_date_format', 'yyyy-MM-dd');
