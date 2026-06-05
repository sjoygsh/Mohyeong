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
  // Mirrors Mihon's `LibraryPreferences.displayMode`
  // (`pref_display_mode_library`). The serialized string values match
  // `LibraryDisplayMode.Serializer` VERBATIM so a backup/restore from the
  // Kotlin build carries the user's choice across.
  static const _key = 'pref_display_mode_library';

  @override
  LibraryDisplayMode build() {
    _loadFromDisk();
    // Mihon's default is CompactGrid.
    return LibraryDisplayMode.compactGrid;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final resolved =
        _decode(prefs.getString(_key)) ?? LibraryDisplayMode.compactGrid;
    if (resolved != state) state = resolved;
  }

  Future<void> setMode(LibraryDisplayMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(mode));
  }

  static LibraryDisplayMode? _decode(String? raw) {
    switch (raw) {
      case 'COMPACT_GRID':
        return LibraryDisplayMode.compactGrid;
      case 'COMFORTABLE_GRID':
        return LibraryDisplayMode.comfortableGrid;
      case 'COVER_ONLY_GRID':
        return LibraryDisplayMode.coverOnlyGrid;
      case 'LIST':
        return LibraryDisplayMode.list;
      default:
        return null;
    }
  }

  static String _encode(LibraryDisplayMode mode) {
    switch (mode) {
      case LibraryDisplayMode.compactGrid:
        return 'COMPACT_GRID';
      case LibraryDisplayMode.comfortableGrid:
        return 'COMFORTABLE_GRID';
      case LibraryDisplayMode.coverOnlyGrid:
        return 'COVER_ONLY_GRID';
      case LibraryDisplayMode.list:
        return 'LIST';
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

/// Boolean Notifier persisted to SharedPreferences under [_key]. Used as
/// the underlying type for every library-badge visibility toggle below —
/// each subclass only differs in its [_key] and [_default]. Mirrors
/// Mihon's `LibraryPreferences` badge entries 1:1 so backups carry over.
abstract class _BoolPrefNotifier extends Notifier<bool> {
  String get _key;
  bool get _default;

  @override
  bool build() {
    _loadFromDisk();
    return _default;
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

/// "Show downloaded count badge on library cards". Off by default in
/// Mihon — the per-card filesystem probe isn't free, and most users only
/// want it when they're triaging offline reads.
class DisplayDownloadBadgeNotifier extends _BoolPrefNotifier {
  @override
  String get _key => 'display_download_badge';
  @override
  bool get _default => false;
}

/// "Show unread count badge on library cards". On by default — the
/// unread count is the headline number on the Library tab.
class DisplayUnreadBadgeNotifier extends _BoolPrefNotifier {
  @override
  String get _key => 'display_unread_badge';
  @override
  bool get _default => true;
}

/// "Show 'Local' chip on cards backed by the built-in Local source"
/// (source id 0). On by default so users can tell side-loaded series
/// apart from extension-fetched ones at a glance.
class DisplayLocalBadgeNotifier extends _BoolPrefNotifier {
  @override
  String get _key => 'display_local_badge';
  @override
  bool get _default => true;
}

/// "Show source language code chip on library cards" — useful when the
/// user follows series across several language editions. Off by default
/// to keep covers clean.
class DisplayLanguageBadgeNotifier extends _BoolPrefNotifier {
  @override
  String get _key => 'display_language_badge';
  @override
  bool get _default => false;
}

/// "Show the continue-reading (play) button on library cards". Off by
/// default in Mihon. When on, a filled play button is overlaid on each
/// card / list row; tapping it resumes the next unread chapter without
/// opening the manga details screen first. Mirrors Mihon's
/// `LibraryPreferences.showContinueReadingButton`
/// (`display_continue_reading_button`, default false).
class ShowContinueReadingButtonNotifier extends _BoolPrefNotifier {
  @override
  String get _key => 'display_continue_reading_button';
  @override
  bool get _default => false;
}

final displayDownloadBadgeProvider =
    NotifierProvider<DisplayDownloadBadgeNotifier, bool>(
  DisplayDownloadBadgeNotifier.new,
);

final showContinueReadingButtonProvider =
    NotifierProvider<ShowContinueReadingButtonNotifier, bool>(
  ShowContinueReadingButtonNotifier.new,
);

final displayUnreadBadgeProvider =
    NotifierProvider<DisplayUnreadBadgeNotifier, bool>(
  DisplayUnreadBadgeNotifier.new,
);

final displayLocalBadgeProvider =
    NotifierProvider<DisplayLocalBadgeNotifier, bool>(
  DisplayLocalBadgeNotifier.new,
);

final displayLanguageBadgeProvider =
    NotifierProvider<DisplayLanguageBadgeNotifier, bool>(
  DisplayLanguageBadgeNotifier.new,
);
