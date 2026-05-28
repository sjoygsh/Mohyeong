import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/manga/model/manga.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'manga_mapper.dart';

/// Thin repository over the `manga_links` Drift table — the cluster table
/// that lets the user mark several local manga rows as alternate sources
/// for the same series (different language scanlations, mirror sources,
/// etc.). The Updates tab joins against this table so chapter activity on
/// a linked manga shows under the primary's cover.
class MangaLinksRepository {
  MangaLinksRepository(this._db);

  final db.AppDatabase _db;

  /// All manga that are linked to [primaryId], ordered by stored priority
  /// (lowest first). Returns an empty list when nothing is linked.
  Future<List<Manga>> getLinked(int primaryId) async {
    final rows = await _db.getLinkedMangas(primaryId).get();
    return rows.map(MangaMapper.fromRow).toList(growable: false);
  }

  /// Live counterpart of [getLinked] for reactive UI (manga details
  /// page).
  Stream<List<Manga>> watchLinked(int primaryId) {
    return _db
        .getLinkedMangas(primaryId)
        .watch()
        .map((rows) => rows.map(MangaMapper.fromRow).toList(growable: false));
  }

  /// Manga that have [linkedId] in their links list. Used to figure out if
  /// the manga the user is looking at is a *linked side* — useful for
  /// hiding the "Add linked source" button on those rows since clusters
  /// are anchored at the primary.
  Future<List<Manga>> getPrimariesOf(int linkedId) async {
    final rows = await _db.getPrimariesOfLinked(linkedId).get();
    return rows.map(MangaMapper.fromRow).toList(growable: false);
  }

  Future<void> link(int primaryId, int linkedId, {int priority = 0}) async {
    if (primaryId == linkedId) return;
    await _db.insertLink(primaryId, linkedId, priority);
  }

  Future<void> unlink(int primaryId, int linkedId) async {
    await _db.deleteLink(primaryId, linkedId);
  }

  /// Drops every link row touching [mangaId], regardless of which side.
  /// Called when a manga is removed from the library so we don't keep
  /// dangling rows pointing at deleted ids — though the FK is also
  /// configured with `ON DELETE CASCADE`, this lets us purge before the
  /// row itself is deleted (useful for "unfavorite" flows that keep the
  /// row but want the link cluster cleared).
  Future<void> clearLinksFor(int mangaId) async {
    await _db.deleteAllLinksForManga(mangaId);
  }

  Future<void> setPriority(int primaryId, int linkedId, int priority) async {
    await _db.updateLinkPriority(priority, primaryId, linkedId);
  }
}

final mangaLinksRepositoryProvider = Provider<MangaLinksRepository>((ref) {
  return MangaLinksRepository(ref.watch(databaseProvider));
});
