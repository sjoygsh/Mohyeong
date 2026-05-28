/// Library grid display mode preference, paralleling
/// `reader_preferences.dart`'s structure: store the selected mode in
/// SharedPreferences under a stable key, expose it through a Riverpod
/// `NotifierProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Library grid display style — four modes matching Mihon's Compact /
/// Comfortable / Cover-only / List options.
enum LibraryDisplayMode {
  /// Cover with the title overlaid at the bottom of the image.
  compactGrid,

  /// Cover with the title rendered below the cover, on the card.
  comfortableGrid,

  /// Cover only, no title. Useful for a denser library at a glance.
  coverOnlyGrid,

  /// Single-column list: thumbnail + title + author. Fits far more rows
  /// at the cost of cover prominence.
  list,
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
      case 'list':
        return LibraryDisplayMode.list;
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
      case LibraryDisplayMode.list:
        return 'list';
    }
  }
}

final libraryDisplayModeProvider =
    NotifierProvider<LibraryDisplayModeNotifier, LibraryDisplayMode>(
  LibraryDisplayModeNotifier.new,
);

/// Sort axes available to the library grid — mirrors Mihon's
/// `LibrarySort.Type` enum. Each axis is paired with a [LibrarySortDirection]
/// in [LibrarySortPref].
enum LibrarySortAxis {
  title,
  lastRead,
  lastUpdate,
  unread,
  totalChapters,
  latestChapter,
  chapterFetchDate,
  dateAdded,
}

enum LibrarySortDirection { ascending, descending }

/// (axis, direction) pair persisted across sessions. The default mirrors
/// Mihon's default: title, ascending.
class LibrarySortPref {
  const LibrarySortPref({
    required this.axis,
    required this.direction,
  });

  final LibrarySortAxis axis;
  final LibrarySortDirection direction;

  static const LibrarySortPref defaults = LibrarySortPref(
    axis: LibrarySortAxis.title,
    direction: LibrarySortDirection.ascending,
  );

  LibrarySortPref copyWith({
    LibrarySortAxis? axis,
    LibrarySortDirection? direction,
  }) {
    return LibrarySortPref(
      axis: axis ?? this.axis,
      direction: direction ?? this.direction,
    );
  }
}

class LibrarySortNotifier extends Notifier<LibrarySortPref> {
  static const _axisKey = 'pref_library_sort_axis';
  static const _dirKey = 'pref_library_sort_direction';

  @override
  LibrarySortPref build() {
    _loadFromDisk();
    return LibrarySortPref.defaults;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final axis = _decodeAxis(prefs.getString(_axisKey)) ??
        LibrarySortPref.defaults.axis;
    final direction = _decodeDirection(prefs.getString(_dirKey)) ??
        LibrarySortPref.defaults.direction;
    final next = LibrarySortPref(axis: axis, direction: direction);
    if (next.axis != state.axis || next.direction != state.direction) {
      state = next;
    }
  }

  /// Tapping the active axis flips direction; tapping a different axis
  /// switches to it with the same direction.
  Future<void> setAxis(LibrarySortAxis axis) async {
    if (state.axis == axis) {
      await _persist(
        state.copyWith(
          direction: state.direction == LibrarySortDirection.ascending
              ? LibrarySortDirection.descending
              : LibrarySortDirection.ascending,
        ),
      );
    } else {
      await _persist(state.copyWith(axis: axis));
    }
  }

  Future<void> _persist(LibrarySortPref next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_axisKey, _encodeAxis(next.axis));
    await prefs.setString(_dirKey, _encodeDirection(next.direction));
  }

  static LibrarySortAxis? _decodeAxis(String? raw) {
    switch (raw) {
      case 'title':
        return LibrarySortAxis.title;
      case 'last_read':
        return LibrarySortAxis.lastRead;
      case 'last_update':
        return LibrarySortAxis.lastUpdate;
      case 'unread':
        return LibrarySortAxis.unread;
      case 'total_chapters':
        return LibrarySortAxis.totalChapters;
      case 'latest_chapter':
        return LibrarySortAxis.latestChapter;
      case 'chapter_fetch':
        return LibrarySortAxis.chapterFetchDate;
      case 'date_added':
        return LibrarySortAxis.dateAdded;
      default:
        return null;
    }
  }

  static String _encodeAxis(LibrarySortAxis axis) {
    switch (axis) {
      case LibrarySortAxis.title:
        return 'title';
      case LibrarySortAxis.lastRead:
        return 'last_read';
      case LibrarySortAxis.lastUpdate:
        return 'last_update';
      case LibrarySortAxis.unread:
        return 'unread';
      case LibrarySortAxis.totalChapters:
        return 'total_chapters';
      case LibrarySortAxis.latestChapter:
        return 'latest_chapter';
      case LibrarySortAxis.chapterFetchDate:
        return 'chapter_fetch';
      case LibrarySortAxis.dateAdded:
        return 'date_added';
    }
  }

  static LibrarySortDirection? _decodeDirection(String? raw) {
    switch (raw) {
      case 'asc':
        return LibrarySortDirection.ascending;
      case 'desc':
        return LibrarySortDirection.descending;
      default:
        return null;
    }
  }

  static String _encodeDirection(LibrarySortDirection dir) {
    switch (dir) {
      case LibrarySortDirection.ascending:
        return 'asc';
      case LibrarySortDirection.descending:
        return 'desc';
    }
  }
}

final librarySortProvider =
    NotifierProvider<LibrarySortNotifier, LibrarySortPref>(
  LibrarySortNotifier.new,
);

/// Toggles the "Most read" carousel on the Library screen. Mirrors
/// Mihon's `show_most_read_carousel` boolean preference (default true).
/// When false, the carousel is hidden regardless of how many items
/// would qualify.
class ShowMostReadCarouselNotifier extends Notifier<bool> {
  static const _key = 'show_most_read_carousel';

  @override
  bool build() {
    _loadFromDisk();
    return true;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_key);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}

final showMostReadCarouselProvider =
    NotifierProvider<ShowMostReadCarouselNotifier, bool>(
  ShowMostReadCarouselNotifier.new,
);
