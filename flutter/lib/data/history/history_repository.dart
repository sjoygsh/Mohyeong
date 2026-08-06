import 'package:drift/drift.dart' show Variable, innerJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/history/model/history.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'history_mapper.dart';

/// Joined history-with-context row for the Updates/History feeds. Mirrors
/// the shape the Kotlin app's HistoryView projects in-memory.
class HistoryWithContext {
  const HistoryWithContext({
    required this.historyId,
    required this.chapterId,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterName,
    required this.chapterNumber,
    required this.readAt,
    required this.timeReadMs,
    required this.source,
    required this.thumbnailUrl,
  });

  final int historyId;
  final int chapterId;
  final int mangaId;
  final String mangaTitle;
  final String chapterName;
  final double chapterNumber;
  final DateTime? readAt;
  final int timeReadMs;

  /// Owning source id. Carried so a row can resolve its cover through the
  /// per-source image headers the rest of the app uses — several sources 403
  /// a cover request that arrives without their referer.
  final int source;
  final String? thumbnailUrl;
}

class HistoryRepository {
  HistoryRepository(this._db);

  final db.AppDatabase _db;

  Future<List<History>> getByMangaId(int mangaId) async {
    final rows = await _db.getHistoryByMangaId(mangaId).get();
    return rows.map(HistoryMapper.fromRow).toList(growable: false);
  }

  /// History for many manga at once, grouped by manga id — the bulk form of
  /// [getByMangaId] for whole-library walks (backup creation). `history` has
  /// no manga_id of its own, so the owning manga comes off the chapter join.
  Future<Map<int, List<History>>> getByMangaIds(Iterable<int> mangaIds) async {
    final ids = mangaIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.history).join([
      innerJoin(_db.chapters, _db.chapters.id.equalsExp(_db.history.chapterId)),
    ])..where(_db.chapters.mangaId.isIn(ids)))
        .get();
    final out = <int, List<History>>{};
    for (final r in rows) {
      final mangaId = r.readTable(_db.chapters).mangaId;
      (out[mangaId] ??= <History>[])
          .add(HistoryMapper.fromRow(r.readTable(_db.history)));
    }
    return out;
  }

  /// Records or extends a read session for a chapter. Time spent reading is
  /// added on top of the existing duration via the SQLDelight-style ON
  /// CONFLICT clause we wrote into `history.drift`.
  Future<void> upsert({
    required int chapterId,
    required DateTime? readAt,
    required int timeReadMs,
  }) async {
    await _db.upsertHistory(
      chapterId,
      readAt?.millisecondsSinceEpoch,
      timeReadMs,
    );
  }

  /// Idempotent history write for the BACKUP RESTORE / SYNC path: the
  /// regular [upsert] ADDS time_read on conflict, so re-applying a backup
  /// (and the file-storage sync's pull-restore-then-push cycle does so
  /// every pass) inflated read-time totals without bound. This takes the
  /// MAX of existing vs incoming instead — net `max(local, backup)`,
  /// matching Kotlin's restorer (`max(item.readDuration, db.time_read)`).
  /// Raw SQL keeps it out of the generated additive query.
  Future<void> upsertAbsolute({
    required int chapterId,
    required int? readAtMs,
    required int timeReadMs,
  }) async {
    await _db.customStatement(
      'INSERT INTO history(chapter_id, last_read, time_read) '
      'VALUES (?1, ?2, ?3) '
      'ON CONFLICT(chapter_id) DO UPDATE SET '
      'last_read = max(last_read, ?2), '
      'time_read = max(time_read, ?3) '
      'WHERE chapter_id = ?1',
      [chapterId, readAtMs ?? 0, timeReadMs],
    );
  }

  Future<void> resetByMangaId(int mangaId) async {
    await _db.resetHistoryByMangaId(mangaId);
  }

  /// Single-row delete used by the per-entry "remove from history" action
  /// on the History tab. Wipes only this `history._id`; the underlying
  /// chapter's `last_page_read` stays intact (Mihon parity — removing
  /// history doesn't reset reading position).
  Future<void> removeById(int historyId) async {
    await (_db.delete(_db.history)..where((t) => t.id.equals(historyId))).go();
  }

  Future<void> removeAll() async {
    await _db.removeAllHistory();
  }

  Future<int> totalReadDurationMs() async {
    final result = await _db.getReadDuration().getSingle();
    return result;
  }

  /// Streams the most recently read chapters (newest first), joined with
  /// chapter + manga metadata so the History tab can render directly.
  /// Rows with last_read = 0 (reset history) are excluded.
  Stream<List<HistoryWithContext>> watchRecent({int limit = 200}) {
    final query = _db.customSelect(
      '''
      SELECT
        H._id AS history_id,
        H.chapter_id,
        H.last_read,
        H.time_read,
        C.name AS chapter_name,
        C.chapter_number,
        M._id AS manga_id,
        M.title AS manga_title,
        M.source AS source,
        M.thumbnail_url
      FROM history H
      JOIN chapters C ON H.chapter_id = C._id
      JOIN mangas M ON C.manga_id = M._id
      WHERE H.last_read IS NOT NULL AND H.last_read > 0
      ORDER BY H.last_read DESC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {_db.history, _db.chapters, _db.mangas},
    );
    return query.watch().map((rows) {
      return rows.map((r) {
        final lastRead = r.read<int?>('last_read');
        return HistoryWithContext(
          historyId: r.read<int>('history_id'),
          chapterId: r.read<int>('chapter_id'),
          mangaId: r.read<int>('manga_id'),
          mangaTitle: r.read<String>('manga_title'),
          chapterName: r.read<String>('chapter_name'),
          chapterNumber: r.read<double>('chapter_number'),
          readAt: lastRead == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(lastRead),
          timeReadMs: r.read<int>('time_read'),
          source: r.read<int>('source'),
          thumbnailUrl: r.read<String?>('thumbnail_url'),
        );
      }).toList(growable: false);
    });
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(databaseProvider));
});
