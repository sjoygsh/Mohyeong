import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chapter/model/chapter.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'chapter_mapper.dart';

class ChapterRepository {
  ChapterRepository(this._db);

  final db.AppDatabase _db;

  Future<List<Chapter>> getByMangaId(int mangaId) async {
    final rows = await _db.getChaptersByMangaId(mangaId).get();
    return rows.map(ChapterMapper.fromRow).toList(growable: false);
  }

  Stream<List<Chapter>> watchByMangaId(int mangaId) {
    return _db.getChaptersByMangaId(mangaId).watch().map(
          (rows) => rows.map(ChapterMapper.fromRow).toList(growable: false),
        );
  }

  Future<int> upsert(Chapter chapter) async {
    return _db
        .into(_db.chapters)
        .insertOnConflictUpdate(ChapterMapper.toCompanion(chapter));
  }

  /// Atomically replace the chapter set for a manga (used after fetching the
  /// latest chapter list from a source).
  Future<void> replaceForManga(int mangaId, List<Chapter> chapters) async {
    await _db.transaction(() async {
      await (_db.delete(_db.chapters)..where((t) => t.mangaId.equals(mangaId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.chapters,
          chapters.map(ChapterMapper.toCompanion).toList(growable: false),
        );
      });
    });
  }
}

final chapterRepositoryProvider = Provider<ChapterRepository>((ref) {
  return ChapterRepository(ref.watch(databaseProvider));
});
