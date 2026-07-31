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
  ///
  /// Note this is NOT part of the unfavourite path — leaving the library
  /// keeps the manga row, and Kotlin keeps the cluster with it, so an
  /// unfavourite/refavourite round trip comes back linked exactly as it was.
  /// Actual row deletion is handled by the FK's `ON DELETE CASCADE`. The one
  /// caller is [makePrimary], which has to clear the old primary's edges
  /// before re-anchoring them.
  Future<void> clearLinksFor(int mangaId) async {
    await _db.deleteAllLinksForManga(mangaId);
  }

  Future<void> setPriority(int primaryId, int linkedId, int priority) async {
    await _db.updateLinkPriority(priority, primaryId, linkedId);
  }

  /// Promotes [newPrimaryId] to be the primary of the cluster anchored at
  /// [oldPrimaryId]. 1:1 with Kotlin's `MakeLinkedPrimary`:
  ///
  ///   before: oldPrimary -> [newPrimary, siblingA, siblingB]
  ///   after:  newPrimary -> [oldPrimary, siblingA, siblingB]
  ///
  /// Clusters are anchored at the primary, so there is no edge to flip —
  /// every row touching the old primary is dropped and re-inserted the other
  /// way round, with the demoted primary taking priority 0 and the siblings
  /// following in their existing order.
  ///
  /// Returns false when there is nothing to do: same id on both sides, or
  /// [newPrimaryId] isn't in the cluster. Caller must have favourited the new
  /// primary first — its library entry becomes the cluster's, so promoting an
  /// unfavourited manga would drop the whole cluster out of the library.
  Future<bool> makePrimary(int oldPrimaryId, int newPrimaryId) async {
    if (oldPrimaryId == newPrimaryId) return false;
    final linked = await getLinked(oldPrimaryId);
    if (!linked.any((m) => m.id == newPrimaryId)) return false;
    // One transaction, unlike Kotlin's loose sequence: the delete has already
    // happened by the time the re-inserts run, so a failure in between would
    // otherwise leave the user with no cluster at all.
    await _db.transaction(() async {
      await _db.deleteAllLinksForManga(oldPrimaryId);
      await _db.insertLink(newPrimaryId, oldPrimaryId, 0);
      var priority = 1;
      for (final sibling in linked) {
        if (sibling.id == newPrimaryId) continue;
        await _db.insertLink(newPrimaryId, sibling.id, priority++);
      }
    });
    return true;
  }
}

final mangaLinksRepositoryProvider = Provider<MangaLinksRepository>((ref) {
  return MangaLinksRepository(ref.watch(databaseProvider));
});
