/// App-level state toggles, ported from Mihon's `BasePreferences`.
library;

import '../preferences/typed_preferences.dart';

/// Mihon `Preference.appStateKey("pref_downloaded_only")` — app-state keys
/// are excluded from backups; matched verbatim for settings-import parity.
const downloadedOnlyKey = '__APP_STATE_pref_downloaded_only';

/// "Downloaded only" mode (More screen switch). While on: the library is
/// forced to the downloaded filter, the per-manga downloaded chapter filter
/// is pinned on, and the reader's chapter navigation skips non-downloaded
/// chapters. Persists across restarts (unlike incognito, which Mihon resets
/// at every launch).
final downloadedOnlyProvider = boolPref(downloadedOnlyKey, false);
