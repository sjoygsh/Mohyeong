import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library/model/library_item.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/update_strategy.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';

/// Reads from the materialised `libraryView` so the Library screen can show
/// per-manga aggregate stats (unread count, latest upload, last read, category
/// memberships) without joining on every refresh. Equivalent to the queries
/// in Mihon's `LibraryRepositoryImpl` / `GetLibraryManga`.
class LibraryRepository {
  LibraryRepository(this._db);

  final db.AppDatabase _db;

  Stream<List<LibraryItem>> watchAll() {
    return _db.select(_db.libraryView).watch().map(
          (rows) => rows.map(_fromRow).toList(growable: false),
        );
  }

  static LibraryItem _fromRow(db.LibraryViewData row) {
    final categoryIds = <int>{};
    for (final part in row.categories.split(',')) {
      final id = int.tryParse(part.trim());
      if (id != null) categoryIds.add(id);
    }
    final manga = Manga(
      id: row.id,
      source: row.source,
      favorite: row.favorite != 0,
      lastUpdate: row.lastUpdate ?? 0,
      nextUpdate: row.nextUpdate ?? 0,
      fetchInterval: row.calculateInterval,
      dateAdded: row.dateAdded,
      viewerFlags: row.viewer,
      chapterFlags: row.chapterFlags,
      coverLastModified: row.coverLastModified,
      url: row.url,
      title: row.title,
      artist: row.artist,
      author: row.author,
      description: row.description,
      genre: _splitGenre(row.genre),
      status: row.status,
      thumbnailUrl: row.thumbnailUrl,
      updateStrategy: UpdateStrategy.fromDb(row.updateStrategy),
      initialized: row.initialized != 0,
      lastModifiedAt: row.lastModifiedAt,
      favoriteModifiedAt: row.favoriteModifiedAt,
      version: row.version,
      notes: row.notes,
    );
    final unread = (row.totalCount - row.readCount).clamp(0, row.totalCount);
    return LibraryItem(
      manga: manga,
      unreadCount: unread,
      totalCount: row.totalCount,
      readCount: row.readCount,
      bookmarkCount: row.bookmarkCount,
      latestUpload: row.latestUpload,
      chapterFetchedAt: row.chapterFetchedAt,
      lastRead: row.lastRead,
      categoryIds: categoryIds,
    );
  }

  static List<String>? _splitGenre(String? raw) {
    if (raw == null) return null;
    if (raw.isEmpty) return const [];
    return raw.split(',');
  }
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(databaseProvider));
});
