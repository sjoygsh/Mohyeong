import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart' as db;
import '../database/database_provider.dart';

/// A row from `updatesView` -- one (manga, chapter) pair representing a
/// newly fetched chapter in a favourited manga. Shape mirrors the Kotlin
/// `UpdatesView` SQLDelight view 1:1, including the `excludedScanlator`
/// outer join introduced in migration 9.sqm.
class LibraryUpdate {
  const LibraryUpdate({
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterId,
    required this.chapterName,
    required this.scanlator,
    required this.chapterUrl,
    required this.read,
    required this.bookmark,
    required this.lastPageRead,
    required this.source,
    required this.thumbnailUrl,
    required this.coverLastModified,
    required this.dateUpload,
    required this.dateFetch,
    required this.excludedScanlator,
  });

  final int mangaId;
  final String mangaTitle;
  final int chapterId;
  final String chapterName;
  final String? scanlator;
  final String chapterUrl;
  final bool read;
  final bool bookmark;
  final int lastPageRead;
  final int source;
  final String? thumbnailUrl;
  final int coverLastModified;
  final int dateUpload;
  final int dateFetch;
  final String? excludedScanlator;

  bool get isScanlatorMuted => excludedScanlator != null;

  factory LibraryUpdate.fromRow(db.UpdatesViewData r) {
    return LibraryUpdate(
      mangaId: r.mangaId,
      mangaTitle: r.mangaTitle,
      chapterId: r.chapterId,
      chapterName: r.chapterName,
      scanlator: r.scanlator,
      chapterUrl: r.chapterUrl,
      read: r.read != 0,
      bookmark: r.bookmark != 0,
      lastPageRead: r.lastPageRead,
      source: r.source,
      thumbnailUrl: r.thumbnailUrl,
      coverLastModified: r.coverLastModified,
      dateUpload: r.dateUpload,
      dateFetch: r.datefetch,
      excludedScanlator: r.excludedScanlator,
    );
  }
}

class UpdatesRepository {
  UpdatesRepository(this._db);

  final db.AppDatabase _db;

  Stream<List<LibraryUpdate>> watchAll() {
    return _db.select(_db.updatesView).watch().map(
          (rows) =>
              rows.map(LibraryUpdate.fromRow).toList(growable: false),
        );
  }
}

final updatesRepositoryProvider = Provider<UpdatesRepository>((ref) {
  return UpdatesRepository(ref.watch(databaseProvider));
});
