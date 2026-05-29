/// Browse-related preferences surfaced under Settings → Browse, mirroring
/// Mihon's `SettingsBrowseScreen`. Keys match the Kotlin app so a settings
/// import carries across.
///
/// [hideInLibraryItemsProvider] is wired into the per-source browse grid
/// (already-favourited results are dropped). [showNsfwSourceProvider] is
/// persisted + shown but stored-only — the installed-source model carries
/// no NSFW flag yet, so there is nothing to filter on.
library;

import '../preferences/typed_preferences.dart';

/// Hide manga that are already in the library from source browse / search
/// result grids.
final hideInLibraryItemsProvider =
    boolPref('pref_hide_in_library_items', false);

/// Surface sources flagged NSFW. Stored-only — no source NSFW flag yet.
final showNsfwSourceProvider = boolPref('pref_show_nsfw_source', true);
