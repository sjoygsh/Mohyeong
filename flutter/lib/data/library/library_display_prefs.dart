/// Library grid display mode preference, paralleling
/// `reader_preferences.dart`'s structure: store the selected mode in
/// SharedPreferences under a stable key, expose it through a Riverpod
/// `NotifierProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Library grid display style — three modes matching Mihon's Compact /
/// Comfortable / Cover-only options.
enum LibraryDisplayMode {
  /// Cover with the title overlaid at the bottom of the image.
  compactGrid,

  /// Cover with the title rendered below the cover, on the card.
  comfortableGrid,

  /// Cover only, no title. Useful for a denser library at a glance.
  coverOnlyGrid,
}

class LibraryDisplayModeNotifier extends Notifier<LibraryDisplayMode> {
  static const _key = 'pref_library_display_mode';

  @override
  LibraryDisplayMode build() {
    _loadFromDisk();
    return LibraryDisplayMode.comfortableGrid;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved = _decode(prefs.getString(_key)) ??
        LibraryDisplayMode.comfortableGrid;
    if (resolved != state) state = resolved;
  }

  Future<void> setMode(LibraryDisplayMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(mode));
  }

  static LibraryDisplayMode? _decode(String? raw) {
    switch (raw) {
      case 'compact':
        return LibraryDisplayMode.compactGrid;
      case 'comfortable':
        return LibraryDisplayMode.comfortableGrid;
      case 'cover_only':
        return LibraryDisplayMode.coverOnlyGrid;
      default:
        return null;
    }
  }

  static String _encode(LibraryDisplayMode mode) {
    switch (mode) {
      case LibraryDisplayMode.compactGrid:
        return 'compact';
      case LibraryDisplayMode.comfortableGrid:
        return 'comfortable';
      case LibraryDisplayMode.coverOnlyGrid:
        return 'cover_only';
    }
  }
}

final libraryDisplayModeProvider =
    NotifierProvider<LibraryDisplayModeNotifier, LibraryDisplayMode>(
  LibraryDisplayModeNotifier.new,
);
