import 'tri_state.dart';
import 'update_strategy.dart';

/// Mirror of `tachiyomi.domain.manga.model.Manga`.
///
/// The chapter-flag bitmask encoding is identical to the Kotlin app so we can
/// read existing rows verbatim out of `mangas.chapter_flags`. Sorting/display
/// constants live as static fields below.
class Manga {
  const Manga({
    required this.id,
    required this.source,
    required this.favorite,
    required this.lastUpdate,
    required this.nextUpdate,
    required this.fetchInterval,
    required this.dateAdded,
    required this.viewerFlags,
    required this.chapterFlags,
    required this.coverLastModified,
    required this.url,
    required this.title,
    required this.artist,
    required this.author,
    required this.description,
    required this.genre,
    required this.status,
    required this.thumbnailUrl,
    required this.updateStrategy,
    required this.initialized,
    required this.lastModifiedAt,
    required this.favoriteModifiedAt,
    required this.version,
    required this.notes,
  });

  final int id;
  final int source;
  final bool favorite;
  final int lastUpdate;
  final int nextUpdate;
  final int fetchInterval;
  final int dateAdded;
  final int viewerFlags;
  final int chapterFlags;
  final int coverLastModified;
  final String url;
  final String title;
  final String? artist;
  final String? author;
  final String? description;

  /// Genre is persisted as a comma-separated `TEXT` in SQLite (Kotlin used
  /// `AS List<String>`). Split happens in the data-layer mapper.
  final List<String>? genre;
  final int status;
  final String? thumbnailUrl;
  final UpdateStrategy updateStrategy;
  final bool initialized;
  final int lastModifiedAt;
  final int? favoriteModifiedAt;
  final int version;
  final String notes;

  /// Returns null when status == COMPLETED, matching Kotlin's
  /// `expectedNextUpdate` getter so the UI hides the "next update" hint for
  /// finished series.
  DateTime? get expectedNextUpdate {
    if (status == _statusCompleted) return null;
    return DateTime.fromMillisecondsSinceEpoch(nextUpdate);
  }

  int get sorting => chapterFlags & chapterSortingMask;
  int get displayMode => chapterFlags & chapterDisplayMask;
  int get unreadFilterRaw => chapterFlags & chapterUnreadMask;
  int get downloadedFilterRaw => chapterFlags & chapterDownloadedMask;
  int get bookmarkedFilterRaw => chapterFlags & chapterBookmarkedMask;

  TriState get unreadFilter {
    switch (unreadFilterRaw) {
      case chapterShowUnread:
        return TriState.enabledIs;
      case chapterShowRead:
        return TriState.enabledNot;
      default:
        return TriState.disabled;
    }
  }

  TriState get bookmarkedFilter {
    switch (bookmarkedFilterRaw) {
      case chapterShowBookmarked:
        return TriState.enabledIs;
      case chapterShowNotBookmarked:
        return TriState.enabledNot;
      default:
        return TriState.disabled;
    }
  }

  bool sortDescending() {
    return (chapterFlags & chapterSortDirMask) == chapterSortDesc;
  }

  Manga copyWith({
    int? id,
    int? source,
    bool? favorite,
    int? lastUpdate,
    int? nextUpdate,
    int? fetchInterval,
    int? dateAdded,
    int? viewerFlags,
    int? chapterFlags,
    int? coverLastModified,
    String? url,
    String? title,
    Object? artist = _sentinel,
    Object? author = _sentinel,
    Object? description = _sentinel,
    Object? genre = _sentinel,
    int? status,
    Object? thumbnailUrl = _sentinel,
    UpdateStrategy? updateStrategy,
    bool? initialized,
    int? lastModifiedAt,
    Object? favoriteModifiedAt = _sentinel,
    int? version,
    String? notes,
  }) {
    return Manga(
      id: id ?? this.id,
      source: source ?? this.source,
      favorite: favorite ?? this.favorite,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      nextUpdate: nextUpdate ?? this.nextUpdate,
      fetchInterval: fetchInterval ?? this.fetchInterval,
      dateAdded: dateAdded ?? this.dateAdded,
      viewerFlags: viewerFlags ?? this.viewerFlags,
      chapterFlags: chapterFlags ?? this.chapterFlags,
      coverLastModified: coverLastModified ?? this.coverLastModified,
      url: url ?? this.url,
      title: title ?? this.title,
      artist: identical(artist, _sentinel) ? this.artist : artist as String?,
      author: identical(author, _sentinel) ? this.author : author as String?,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      genre: identical(genre, _sentinel) ? this.genre : genre as List<String>?,
      status: status ?? this.status,
      thumbnailUrl: identical(thumbnailUrl, _sentinel)
          ? this.thumbnailUrl
          : thumbnailUrl as String?,
      updateStrategy: updateStrategy ?? this.updateStrategy,
      initialized: initialized ?? this.initialized,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      favoriteModifiedAt: identical(favoriteModifiedAt, _sentinel)
          ? this.favoriteModifiedAt
          : favoriteModifiedAt as int?,
      version: version ?? this.version,
      notes: notes ?? this.notes,
    );
  }

  /// Empty placeholder, matches `Manga.create()` in Kotlin.
  factory Manga.empty() => const Manga(
        id: -1,
        url: '',
        title: '',
        source: -1,
        favorite: false,
        lastUpdate: 0,
        nextUpdate: 0,
        fetchInterval: 0,
        dateAdded: 0,
        viewerFlags: 0,
        chapterFlags: 0,
        coverLastModified: 0,
        artist: null,
        author: null,
        description: null,
        genre: null,
        status: 0,
        thumbnailUrl: null,
        updateStrategy: UpdateStrategy.alwaysUpdate,
        initialized: false,
        lastModifiedAt: 0,
        favoriteModifiedAt: null,
        version: 0,
        notes: '',
      );

  // ---------- bitmask constants (match Kotlin Manga.Companion) ---------------

  static const int showAll = 0x00000000;

  static const int chapterSortDesc = 0x00000000;
  static const int chapterSortAsc = 0x00000001;
  static const int chapterSortDirMask = 0x00000001;

  static const int chapterShowUnread = 0x00000002;
  static const int chapterShowRead = 0x00000004;
  static const int chapterUnreadMask = 0x00000006;

  static const int chapterShowDownloaded = 0x00000008;
  static const int chapterShowNotDownloaded = 0x00000010;
  static const int chapterDownloadedMask = 0x00000018;

  static const int chapterShowBookmarked = 0x00000020;
  static const int chapterShowNotBookmarked = 0x00000040;
  static const int chapterBookmarkedMask = 0x00000060;

  static const int chapterSortingSource = 0x00000000;
  static const int chapterSortingNumber = 0x00000100;
  static const int chapterSortingUploadDate = 0x00000200;
  static const int chapterSortingAlphabet = 0x00000300;
  static const int chapterSortingMask = 0x00000300;

  static const int chapterDisplayName = 0x00000000;
  static const int chapterDisplayNumber = 0x00100000;
  static const int chapterDisplayMask = 0x00100000;

  /// Matches SManga.COMPLETED in source-api so `expectedNextUpdate` lines up.
  static const int _statusCompleted = 2;
}

/// Private sentinel for copyWith nullable params (so we can distinguish
/// "explicitly set to null" from "not provided"). Dart 3.12 lacks the kind
/// of optional named-parameter sentinels Kotlin gets for free.
const Object _sentinel = Object();
