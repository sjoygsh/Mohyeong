import '../../manga/model/manga.dart';

/// A row in the Library screen: a favorited [Manga] joined with the
/// aggregate stats the libraryView projects (chapter counts, fetched-at,
/// last-read, category memberships).
///
/// Mirrors Mihon's `LibraryItem` data class in
/// `eu.kanade.tachiyomi.ui.library.LibraryItem`.
class LibraryItem {
  const LibraryItem({
    required this.manga,
    required this.unreadCount,
    required this.totalCount,
    required this.readCount,
    required this.bookmarkCount,
    required this.latestUpload,
    required this.chapterFetchedAt,
    required this.lastRead,
    required this.categoryIds,
  });

  final Manga manga;

  /// Chapters where read == 0. Excluded scanlators do not contribute.
  final int unreadCount;
  final int totalCount;
  final int readCount;
  final int bookmarkCount;

  /// Max(chapters.date_upload) for this manga.
  final int latestUpload;

  /// Max(chapters.date_fetch) for this manga.
  final int chapterFetchedAt;

  /// Max(history.last_read) for this manga.
  final int lastRead;

  /// Categories the manga belongs to. The system category (0) is included
  /// when the manga has no explicit categories — the libraryView coalesces
  /// to '0' in that case.
  final Set<int> categoryIds;

  bool inCategory(int id) => categoryIds.contains(id);
}
