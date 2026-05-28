import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/update_strategy.dart';
import '../../domain/source/model/source_manga.dart';
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

  /// Counts favourites grouped by source id. Used by the migrate-source
  /// screen so the user can see which installed sources still have
  /// manga to migrate off of. Returns `Map<sourceId, count>` ordered
  /// descending by count.
  Future<Map<int, int>> getFavoritesGroupedBySource() async {
    final rows = await _db.customSelect(
      'SELECT source, COUNT(*) AS cnt FROM mangas '
      'WHERE favorite = 1 GROUP BY source ORDER BY cnt DESC',
      readsFrom: {_db.mangas},
    ).get();
    return {
      for (final r in rows) r.read<int>('source'): r.read<int>('cnt'),
    };
  }

  /// Returns every favourited manga belonging to [sourceId]. Used by
  /// the migrate-source flow to list the manga the user might want to
  /// migrate one at a time.
  Future<List<Manga>> getFavoritesBySource(int sourceId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM mangas WHERE favorite = 1 AND source = ?1',
      variables: [Variable<int>(sourceId)],
      readsFrom: {_db.mangas},
    ).get();
    return rows
        .map((r) => MangaMapper.fromRow(_db.mangas.map(r.data)))
        .toList(growable: false);
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

  /// Mihon-parity duplicate detection used when the user adds a manga
  /// to their library: returns favourited manga (excluding [excludeId])
  /// whose title contains [title] as a case-insensitive substring. The
  /// Kotlin version also matches via shared tracker rows (manga_sync
  /// same sync_id + remote_id) — skipped here; title substring catches
  /// the common case and tracker dedup is rare.
  Future<List<Manga>> findFavoritesWithSimilarTitle(
    int excludeId,
    String title,
  ) async {
    final needle = title.trim().toLowerCase();
    if (needle.isEmpty) return const <Manga>[];
    final rows = await _db.customSelect(
      'SELECT * FROM mangas '
      'WHERE favorite = 1 AND _id != ?1 '
      'AND lower(title) LIKE \'%\' || ?2 || \'%\'',
      variables: [Variable<int>(excludeId), Variable<String>(needle)],
      readsFrom: {_db.mangas},
    ).get();
    return rows
        .map((r) => MangaMapper.fromRow(_db.mangas.map(r.data)))
        .toList(growable: false);
  }

  /// Insert-or-update on PK. Returns the manga's id (filling in the
  /// auto-assigned value on insert).
  Future<int> upsert(Manga manga) async {
    final companion = MangaMapper.toCompanion(manga);
    return _db.into(_db.mangas).insertOnConflictUpdate(companion);
  }

  /// Insert a fresh manga row for a [candidate] returned by a source
  /// listing. Used by flows like the migration screen that need to
  /// land on a target manga before the library updater has run for it.
  /// Resolves an existing row when (url, sourceId) already exists.
  Future<Manga> insertFromSource({
    required SourceManga candidate,
    required int sourceId,
  }) async {
    final existing = await getByUrlAndSource(candidate.url, sourceId);
    if (existing != null) return existing;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final companion = db.MangasCompanion.insert(
      source: sourceId,
      url: candidate.url,
      title: candidate.title,
      artist: Value(candidate.artist),
      author: Value(candidate.author),
      description: Value(candidate.description),
      genre: Value(candidate.genre),
      status: candidate.status,
      thumbnailUrl: Value(candidate.thumbnailUrl),
      favorite: 0,
      lastUpdate: const Value(0),
      nextUpdate: const Value(0),
      initialized: candidate.initialized ? 1 : 0,
      viewer: 0,
      chapterFlags: 0,
      coverLastModified: 0,
      dateAdded: nowMs,
      updateStrategy: Value(UpdateStrategy.alwaysUpdate.dbValue),
      calculateInterval: const Value(0),
      lastModifiedAt: Value(nowMs),
      favoriteModifiedAt: const Value(null),
      version: const Value(0),
      isSyncing: const Value(0),
      notes: const Value(''),
    );
    final newId =
        await _db.into(_db.mangas).insertOnConflictUpdate(companion);
    final inserted = await getById(newId);
    if (inserted == null) {
      throw StateError('Inserted manga row missing after insertFromSource.');
    }
    return inserted;
  }

  Future<void> deleteById(int id) async {
    await (_db.delete(_db.mangas)..where((t) => t.id.equals(id))).go();
  }

  /// Overwrite the `chapter_flags` bitfield (chapter sort/filter/display
  /// bits) for a single manga. Used by the chapter settings sheet on the
  /// manga details screen. Bumps `last_modified_at` for sync ordering.
  Future<void> setChapterFlags(int id, int flags) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.mangas)..where((t) => t.id.equals(id))).write(
      db.MangasCompanion(
        chapterFlags: Value(flags),
        lastModifiedAt: Value(nowMs),
      ),
    );
  }

  /// Overwrite the `viewer` bitfield (reading mode + reserved bits) for a
  /// single manga. Used by the reader's "Reading mode" picker to apply a
  /// per-manga override. Bumps `last_modified_at` so sync clients pick up
  /// the change.
  Future<void> setViewerFlags(int id, int flags) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.mangas)..where((t) => t.id.equals(id))).write(
      db.MangasCompanion(
        viewer: Value(flags),
        lastModifiedAt: Value(nowMs),
      ),
    );
  }

  /// Overwrite the per-manga `notes` column (free-form markdown text the
  /// user keeps about a series). Empty string clears the row's notes.
  /// Bumps `last_modified_at` for sync ordering.
  Future<void> setNotes(int id, String notes) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.mangas)..where((t) => t.id.equals(id))).write(
      db.MangasCompanion(
        notes: Value(notes),
        lastModifiedAt: Value(nowMs),
      ),
    );
  }

  /// Toggle the library state of an existing manga without touching the
  /// rest of its row. Adds `dateAdded` when entering the library (matches
  /// the Kotlin behaviour so categorization-by-date sort works), and
  /// stamps `favoriteModifiedAt` for sync ordering.
  Future<void> setFavorite(int id, bool favorite) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.mangas)..where((t) => t.id.equals(id))).write(
      db.MangasCompanion(
        favorite: Value(favorite ? 1 : 0),
        dateAdded: favorite ? Value(nowMs) : const Value.absent(),
        favoriteModifiedAt: Value(nowMs),
        lastModifiedAt: Value(nowMs),
      ),
    );
  }
}

final mangaRepositoryProvider = Provider<MangaRepository>((ref) {
  return MangaRepository(ref.watch(databaseProvider));
});
