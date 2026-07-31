import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart' as db;
import '../database/database_provider.dart';

/// CRUD over `scanlator_priority`. Equivalent to Mihon's
/// `GetScanlatorPriorities` / `SetScanlatorPriorities` interactors.
///
/// The list is an ORDER, not a set: position 0 is the most preferred
/// scanlator. When several scanlators publish the same chapter number, the
/// chapter list keeps only the highest-ranked one — see
/// `applyScanlatorPriority`. Scanlators with no stored priority are absent
/// from the list and never win on rank.
class ScanlatorPriorityRepository {
  ScanlatorPriorityRepository(this._db);

  final db.AppDatabase _db;

  Future<List<String>> getByMangaId(int mangaId) async {
    final rows = await _db.getPrioritiesByMangaId(mangaId).get();
    return [for (final r in rows) r.scanlator];
  }

  Stream<List<String>> watchByMangaId(int mangaId) {
    return _db
        .getPrioritiesByMangaId(mangaId)
        .watch()
        .map((rows) => [for (final r in rows) r.scanlator]);
  }

  /// Replaces the stored order for [mangaId] with [ordered], most preferred
  /// first. Wrapped in a transaction so a reader never observes the list
  /// half-cleared, which would briefly un-rank every scanlator.
  Future<void> setForManga(int mangaId, List<String> ordered) async {
    await _db.transaction(() async {
      await _db.clearPrioritiesForManga(mangaId);
      for (var i = 0; i < ordered.length; i++) {
        await _db.insertScanlatorPriority(mangaId, ordered[i], i);
      }
    });
  }
}

final scanlatorPriorityRepositoryProvider =
    Provider<ScanlatorPriorityRepository>((ref) {
  return ScanlatorPriorityRepository(ref.watch(databaseProvider));
});
