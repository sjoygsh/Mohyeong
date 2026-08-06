import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart' as db;
import '../database/database_provider.dart';

/// A row from `updatesView` -- one (manga, chapter) pair representing a
/// newly fetched chapter in a favourited manga (or a manga linked to one).
/// Shape mirrors the Kotlin `UpdatesView` SQLDelight view 1:1, including
/// the `excludedScanlator` outer join introduced in migration 9.sqm.
///
/// When the underlying manga is on the *linked* side of a `manga_links`
/// cluster, [mangaId] / [mangaTitle] / [thumbnailUrl] / [coverLastModified]
/// are replaced with the primary's values so the row visually attaches to
/// the cluster entry, while [source] and the chapter fields still refer to
/// the source that actually delivered the chapter. [isLinkedAttribution]
/// reports which mode the row is in.
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
    required this.isLinkedAttribution,
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
  final bool isLinkedAttribution;

  bool get isScanlatorMuted => excludedScanlator != null;

  factory LibraryUpdate.fromRow(
    db.UpdatesViewData r, {
    db.GetAllLinkedWithPrimaryResult? primary,
  }) {
    return LibraryUpdate(
      mangaId: primary?.id ?? r.mangaId,
      mangaTitle: primary?.title ?? r.mangaTitle,
      chapterId: r.chapterId,
      chapterName: r.chapterName,
      scanlator: r.scanlator,
      chapterUrl: r.chapterUrl,
      read: r.read != 0,
      bookmark: r.bookmark != 0,
      lastPageRead: r.lastPageRead,
      source: r.source,
      thumbnailUrl: primary?.thumbnailUrl ?? r.thumbnailUrl,
      coverLastModified: primary?.coverLastModified ?? r.coverLastModified,
      dateUpload: r.dateUpload,
      dateFetch: r.datefetch,
      excludedScanlator: r.excludedScanlator,
      isLinkedAttribution: primary != null,
    );
  }
}

class UpdatesRepository {
  UpdatesRepository(this._db);

  final db.AppDatabase _db;

  /// Updates newer than [after], newest first, capped at [limit].
  ///
  /// Mihon's Updates screen subscribes with `Calendar.getInstance().apply {
  /// add(Calendar.MONTH, -3) }` -- it has never shown the whole table -- and
  /// the bound matters here for a second reason: Drift invalidates per table,
  /// so every `setLastPageRead` re-runs this query even though Home is not the
  /// visible tab. Unbounded, that was the entire chapters/mangas join on each
  /// page turn.
  Stream<List<LibraryUpdate>> watchAll({
    Duration window = const Duration(days: 90),
    int limit = 500,
  }) {
    final after = DateTime.now().subtract(window).millisecondsSinceEpoch;
    final query = _db.select(_db.updatesView)
      ..where((t) => t.datefetch.isBiggerOrEqualValue(after))
      // The view carries its own ORDER BY, but SQLite only guarantees the
      // outer LIMIT picks the newest rows if the outer query orders too.
      ..orderBy([(t) => OrderingTerm.desc(t.datefetch)])
      ..limit(limit);
    return query.watch().asyncMap((rows) async {
      // Re-query the linked->primary map on every emission. The link set
      // is small (one row per cluster edge) and the view itself already
      // reacts to manga_links changes, so this stays in sync.
      final linkedRows = await _db.getAllLinkedWithPrimary().get();
      final linkedToPrimary = <int, db.GetAllLinkedWithPrimaryResult>{
        for (final r in linkedRows) r.linkedMangaId: r,
      };
      return rows
          .map((r) => LibraryUpdate.fromRow(
                r,
                primary: linkedToPrimary[r.mangaId],
              ))
          .toList(growable: false);
    });
  }
}

final updatesRepositoryProvider = Provider<UpdatesRepository>((ref) {
  return UpdatesRepository(ref.watch(databaseProvider));
});
