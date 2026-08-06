import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart' as db;
import '../database/database_provider.dart';

/// CRUD over `excluded_scanlators`. Equivalent to Mihon's
/// `ExcludedScanlatorsRepository`.
///
/// The `libraryView` already filters out chapters whose scanlator is in
/// this set when computing per-manga aggregates (totalCount / readCount
/// etc.), so adding rows here makes excluded chapters disappear from
/// library badges *and* from the per-manga chapter list (filter applied
/// in the manga-details screen).
class ExcludedScanlatorsRepository {
  ExcludedScanlatorsRepository(this._db);

  final db.AppDatabase _db;

  Future<Set<String>> getByMangaId(int mangaId) async {
    final rows = await _db.getExcludedScanlatorsByMangaId(mangaId).get();
    return rows.toSet();
  }

  /// Excluded scanlators for many manga at once, grouped by manga id — the
  /// bulk form of [getByMangaId] for whole-library walks (backup creation).
  Future<Map<int, Set<String>>> getByMangaIds(Iterable<int> mangaIds) async {
    final ids = mangaIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.excludedScanlators)
          ..where((t) => t.mangaId.isIn(ids)))
        .get();
    final out = <int, Set<String>>{};
    for (final r in rows) {
      (out[r.mangaId] ??= <String>{}).add(r.scanlator);
    }
    return out;
  }

  Stream<Set<String>> watchByMangaId(int mangaId) {
    return _db.getExcludedScanlatorsByMangaId(mangaId).watch().map((r) =>
        r.toSet());
  }

  /// Replace the manga's excluded scanlator set with [scanlators]. Wraps
  /// the inserts in a transaction so callers always see a consistent set.
  Future<void> setForManga(int mangaId, Set<String> scanlators) async {
    await _db.transaction(() async {
      final existing = await getByMangaId(mangaId);
      final toRemove = existing.difference(scanlators).toList();
      if (toRemove.isNotEmpty) {
        await _db.removeExcludedScanlators(mangaId, toRemove);
      }
      for (final s in scanlators.difference(existing)) {
        await _db.insertExcludedScanlator(mangaId, s);
      }
    });
  }
}

final excludedScanlatorsRepositoryProvider =
    Provider<ExcludedScanlatorsRepository>((ref) {
  return ExcludedScanlatorsRepository(ref.watch(databaseProvider));
});
