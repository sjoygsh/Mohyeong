/// Browse-related preferences surfaced under Settings → Browse, mirroring
/// Mihon's `SettingsBrowseScreen`. Keys match the Kotlin app so a settings
/// import carries across.
///
/// [hideInLibraryItemsProvider] is wired into the per-source browse grid
/// (already-favourited results are dropped).
///
/// Mihon's `pref_show_nsfw_source` has no provider here: it gates on a flag
/// read from each extension APK's manifest metadata, and the JS extension
/// contract carries nothing equivalent. A backup still round-trips the key —
/// the creator dumps every SharedPreferences entry and the restorer replays
/// them by key, neither one working from a list of names.
library;

import '../preferences/typed_preferences.dart';

/// Hide manga that are already in the library from source browse / search
/// result grids.
///
/// The key is `browse_hide_in_library_items`. `pref_hide_in_library_items` —
/// what this used to be — is the Kotlin app's STRING RESOURCE id for the
/// switch's label, not its storage key, and the two sit next to each other in
/// `SettingsBrowseScreen`. Reading the label id meant a settings import and an
/// in-place upgrade both silently dropped this choice, in a file whose own
/// header promises the keys match. The old spelling is still read once so
/// nobody who set it here loses it.
final hideInLibraryItemsProvider = boolPref(
  'browse_hide_in_library_items',
  false,
  alsoRead: const ['pref_hide_in_library_items'],
);

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
