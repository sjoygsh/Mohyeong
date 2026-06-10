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

/// How source browse / search results render. Mirrors Kotlin's
/// `sourceDisplayMode` (`pref_display_mode_catalogue`), which serialises
/// `LibraryDisplayMode` by name — values kept verbatim for import parity.
enum SourceDisplayMode {
  compactGrid('COMPACT_GRID', 'Compact grid'),
  comfortableGrid('COMFORTABLE_GRID', 'Comfortable grid'),
  list('LIST', 'List');

  const SourceDisplayMode(this.storageName, this.label);

  /// Serialized Kotlin name.
  final String storageName;

  /// Verbatim Mihon label (action_display_grid / _comfortable_grid / _list).
  final String label;

  static SourceDisplayMode fromName(String? name) {
    for (final v in values) {
      if (v.storageName == name) return v;
    }
    return SourceDisplayMode.compactGrid;
  }
}

/// Active browse display mode, stored by serialized name.
final sourceDisplayModeProvider =
    stringPref('pref_display_mode_catalogue', 'COMPACT_GRID');
