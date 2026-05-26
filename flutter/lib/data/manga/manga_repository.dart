import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/manga/model/manga.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'manga_mapper.dart';

/// Domain-facing repository over the `mangas` Drift table. Equivalent to the
/// Kotlin `MangaRepositoryImpl`.
///
/// Reads return domain `Manga` objects. Writes accept domain objects and
/// translate to companions via `MangaMapper.toCompanion`.
class MangaRepository {
  MangaRepository(this._db);

  final db.AppDatabase _db;

  Future<Manga?> getById(int id) async {
    final row = await _db.getMangaById(id).getSingleOrNull();
    return row == null ? null : MangaMapper.fromRow(row);
  }

  Future<Manga?> getByUrlAndSource(String url, int source) async {
    final row = await _db.getMangaByUrlAndSource(url, source).getSingleOrNull();
    return row == null ? null : MangaMapper.fromRow(row);
  }

  Stream<Manga?> watchById(int id) {
    return _db
        .getMangaById(id)
        .watchSingleOrNull()
        .map((row) => row == null ? null : MangaMapper.fromRow(row));
  }

  Future<List<Manga>> getFavorites() async {
    final rows = await _db.getFavorites().get();
    return rows.map(MangaMapper.fromRow).toList(growable: false);
  }

  Stream<List<Manga>> watchFavorites() {
    return _db.getFavorites().watch().map(
          (rows) => rows.map(MangaMapper.fromRow).toList(growable: false),
        );
  }

  Future<List<Manga>> getAll() async {
    final rows = await _db.getAllManga().get();
    return rows.map(MangaMapper.fromRow).toList(growable: false);
  }

  /// Insert-or-update on PK. Returns the manga's id (filling in the
  /// auto-assigned value on insert).
  Future<int> upsert(Manga manga) async {
    final companion = MangaMapper.toCompanion(manga);
    return _db.into(_db.mangas).insertOnConflictUpdate(companion);
  }

  Future<void> deleteById(int id) async {
    await (_db.delete(_db.mangas)..where((t) => t.id.equals(id))).go();
  }
}

final mangaRepositoryProvider = Provider<MangaRepository>((ref) {
  return MangaRepository(ref.watch(databaseProvider));
});
