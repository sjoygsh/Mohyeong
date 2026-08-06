import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/chapter/model/chapter.dart';
import '../../domain/chapter/model/no_chapters_exception.dart';
import '../../domain/source/model/source_chapter.dart';
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

  /// Chapters for many manga at once, grouped by manga id. For whole-library
  /// walks (backup creation) where one query per favourite is the cost that
  /// matters; ids with no chapters are absent from the map.
  Future<Map<int, List<Chapter>>> getByMangaIds(Iterable<int> mangaIds) async {
    final ids = mangaIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.chapters)
          ..where((t) => t.mangaId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.sourceOrder)]))
        .get();
    final out = <int, List<Chapter>>{};
    for (final r in rows) {
      (out[r.mangaId] ??= <Chapter>[]).add(ChapterMapper.fromRow(r));
    }
    return out;
  }

  /// The named chapters, in no particular order.
  ///
  /// For the bulk actions on feeds that already know exactly which chapter
  /// ids the user picked and only need the full rows to act on them. Reading
  /// each owning series whole to sieve a handful out costs the length of the
  /// series rather than the length of the selection.
  Future<List<Chapter>> getByIds(Iterable<int> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return const <Chapter>[];
    final rows =
        await (_db.select(_db.chapters)..where((t) => t.id.isIn(list))).get();
    return rows.map(ChapterMapper.fromRow).toList(growable: false);
  }

  /// Unread chapters in READING order, oldest first.
  ///
  /// `sourceOrder` 0 is the NEWEST chapter, so reading order is descending —
  /// resume and "download the next N" both want the oldest unread, never the
  /// latest release. [limit] caps the result; 1 answers "what do I open".
  ///
  /// The alternative is loading every chapter of the series and sieving in
  /// Dart, which is what resume did — ~17ms of deserialization on a long
  /// series to find one row, on the tap that is supposed to open the reader.
  Future<List<Chapter>> unreadInReadingOrder(int mangaId, {int? limit}) async {
    final query = _db.select(_db.chapters)
      ..where((t) => t.mangaId.equals(mangaId) & t.read.equals(0))
      ..orderBy([(t) => OrderingTerm.desc(t.sourceOrder)]);
    if (limit != null) query.limit(limit);
    final rows = await query.get();
    return rows.map(ChapterMapper.fromRow).toList(growable: false);
  }

  /// The chapter a "continue reading" affordance should open, or null when
  /// the series is fully read.
  Future<Chapter?> nextUnread(int mangaId) async {
    final rows = await unreadInReadingOrder(mangaId, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Just the two date columns the fetch-interval calculation reads.
  ///
  /// It only ever needs a handful of distinct days, and deserializing a
  /// 3,800-chapter series into full [Chapter] objects to find them costs
  /// ~17ms — paid once per manga per library sweep and again on every
  /// details-screen open.
  Future<List<(int, int)>> intervalDatesByMangaId(int mangaId) async {
    final rows = await _db.customSelect(
      'SELECT date_upload, date_fetch FROM chapters WHERE manga_id = ?1',
      variables: [Variable<int>(mangaId)],
      readsFrom: {_db.chapters},
    ).get();
    return [
      for (final r in rows)
        (r.read<int>('date_upload'), r.read<int>('date_fetch')),
    ];
  }

  Stream<List<Chapter>> watchByMangaId(int mangaId) {
    return _db.getChaptersByMangaId(mangaId).watch().map(
          (rows) => rows.map(ChapterMapper.fromRow).toList(growable: false),
        );
  }

  /// (total, unread) chapter counts for EVERY manga in one grouped query.
  /// The library-update eligibility filter needs only these flags — loading
  /// each favourite's full chapter list to compute them was an N+1 that
  /// deserialized thousands of rows per sweep.
  Future<Map<int, ({int total, int unread})>> readStateCountsByManga() async {
    final rows = await _db.customSelect(
      'SELECT manga_id, COUNT(*) AS total, '
      'SUM(CASE WHEN read = 0 THEN 1 ELSE 0 END) AS unread '
      'FROM chapters GROUP BY manga_id',
      readsFrom: {_db.chapters},
    ).get();
    return {
      for (final r in rows)
        r.read<int>('manga_id'): (
          total: r.read<int>('total'),
          unread: r.read<int>('unread'),
        ),
    };
  }

  Future<int> upsert(Chapter chapter) async {
    return _db
        .into(_db.chapters)
        .insertOnConflictUpdate(ChapterMapper.toCompanion(chapter));
  }

  /// Flip the read flag and (when marking unread) reset the saved page
  /// position. Bumps `last_modified_at` + `version` so sync clients pick
  /// up the change.
  Future<void> setRead(int chapterId, bool read) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
        .write(db.ChaptersCompanion(
      read: Value(read ? 1 : 0),
      lastPageRead: read ? const Value.absent() : const Value(0),
      lastModifiedAt: Value(nowMs),
    ));
  }

  Future<void> setBookmark(int chapterId, bool bookmark) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
        .write(db.ChaptersCompanion(
      bookmark: Value(bookmark ? 1 : 0),
      lastModifiedAt: Value(nowMs),
    ));
  }

  /// Overwrites the per-chapter `bookmark_note` text. Empty string clears
  /// the column. Bumps `last_modified_at` for sync ordering. Doesn't
  /// touch the `bookmark` flag — callers decide whether saving a note
  /// should also flip the chapter into the bookmarked state.
  Future<void> setBookmarkNote(int chapterId, String note) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final trimmed = note.trim();
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
        .write(db.ChaptersCompanion(
      bookmarkNote: Value(trimmed.isEmpty ? null : trimmed),
      lastModifiedAt: Value(nowMs),
    ));
  }

  /// `url -> chapter id` for one manga, without deserializing the rows.
  ///
  /// Backup restore resolves its history rows (which reference chapters by
  /// URL on the wire) through this map, per manga, on every sync cycle — and
  /// building it from full [Chapter] objects costs ~17ms on a long series for
  /// two columns' worth of answer.
  Future<Map<String, int>> chapterIdsByUrl(int mangaId) async {
    final rows = await _db.customSelect(
      'SELECT _id, url FROM chapters WHERE manga_id = ?1',
      variables: [Variable<int>(mangaId)],
      readsFrom: {_db.chapters},
    ).get();
    return {for (final r in rows) r.read<String>('url'): r.read<int>('_id')};
  }

  /// The distinct chapter NUMBERS the reader has already read in this manga,
  /// recognized numbers only (`chapter_number >= 0`).
  ///
  /// Same shape as [intervalDatesByMangaId]: the auto-download filter wants a
  /// set of numbers, and deserializing a 3,800-chapter series into full
  /// [Chapter] objects to build it costs ~17ms — once per manga per library
  /// sweep, when download-new-unread-only is on.
  Future<Set<double>> readChapterNumbers(int mangaId) async {
    final rows = await _db.customSelect(
      'SELECT DISTINCT chapter_number FROM chapters '
      'WHERE manga_id = ?1 AND read != 0 AND chapter_number >= 0',
      variables: [Variable<int>(mangaId)],
      readsFrom: {_db.chapters},
    ).get();
    return {for (final r in rows) r.read<double>('chapter_number')};
  }

  /// Merge progress into many chapters at once: one UPDATE per chapter with
  /// whichever of read / bookmark / lastPageRead the caller supplies, the
  /// whole thing in a single transaction.
  ///
  /// The migration path (copying progress onto the manga you migrated to) did
  /// this a column at a time, unbatched and untransacted — up to three round
  /// trips per matched chapter pair, so a long series was thousands. Null
  /// fields are left alone; `read: true` deliberately does NOT reset
  /// lastPageRead, matching [setRead].
  Future<void> mergeProgress(
    List<({int chapterId, bool? read, bool? bookmark, int? lastPageRead})>
        updates,
  ) async {
    if (updates.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.batch((b) {
        for (final u in updates) {
          b.update(
            _db.chapters,
            db.ChaptersCompanion(
              read: u.read == null ? const Value.absent() : Value(u.read! ? 1 : 0),
              bookmark: u.bookmark == null
                  ? const Value.absent()
                  : Value(u.bookmark! ? 1 : 0),
              lastPageRead: u.lastPageRead == null
                  ? const Value.absent()
                  : Value(u.lastPageRead!),
              lastModifiedAt: Value(nowMs),
            ),
            where: (t) => t.id.equals(u.chapterId),
          );
        }
      });
    });
  }

  /// Save the user's current page within a chapter. Called by the reader
  /// on every page change; the row also receives a `lastModifiedAt` bump
  /// so sync clients pick up the position.
  Future<void> setLastPageRead(int chapterId, int page) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.chapters)..where((t) => t.id.equals(chapterId)))
        .write(db.ChaptersCompanion(
      lastPageRead: Value(page),
      lastModifiedAt: Value(nowMs),
    ));
  }

  /// Reconciles a freshly fetched chapter list against the persisted rows for
  /// a manga, preserving local state (read/bookmark/lastPageRead) on rows
  /// that already exist (matched by URL). Returns the chapters that are new
  /// to the DB — used to surface "you have new updates" entries in the
  /// Updates tab. Mirrors the Kotlin `syncChaptersWithSource` behaviour.
  ///
  /// Mihon parity:
  /// - chapters keyed by URL within (manga, url) — not deleted if missing
  ///   from the new fetch (sources sometimes omit older chapters).
  /// - dateFetch is stamped now() on newly inserted chapters only.
  /// - sourceOrder is reassigned by index in the fetched list (so the order
  ///   the source returns wins).
  /// - an empty fetch from a non-local source throws [NoChaptersException]
  ///   rather than reporting a successful no-op ([isLocalSource] opts a local
  ///   manga out, as Kotlin's `!source.isLocal()` does).
  Future<List<Chapter>> syncChaptersWithSource(
    int mangaId,
    List<SourceChapter> fetched, {
    bool isLocalSource = false,
  }) async {
    if (fetched.isEmpty) {
      if (isLocalSource) return const [];
      throw const NoChaptersException();
    }
    // One transaction around the prune + insert + update writes: without it
    // drift query streams emit each intermediate state (the open details
    // screen flickers mid-sync), and a failure after the prune permanently
    // drops the pruned rows before their replacements land.
    return _db.transaction(() => _syncChaptersInTxn(mangaId, fetched));
  }

  Future<List<Chapter>> _syncChaptersInTxn(
    int mangaId,
    List<SourceChapter> fetched,
  ) async {
    final existing = await getByMangaId(mangaId);

    // Dedupe the source list by URL. A misbehaving extension can return the
    // same chapter many times (observed: a source whose API repeated pages
    // inflated a 521-chapter manga to 4401 rows); without this each copy
    // became a separate DB row.
    final sourceUrls = <String>{};
    final deduped = <SourceChapter>[];
    for (final s in fetched) {
      if (sourceUrls.add(s.url)) deduped.add(s);
    }

    // Canonical existing row per URL, preferring one that carries progress so
    // collapsing any pre-existing duplicate rows never drops read state.
    final existingByUrl = <String, Chapter>{};
    for (final c in existing) {
      final prior = existingByUrl[c.url];
      if (prior == null) {
        existingByUrl[c.url] = c;
      } else {
        final priorHasProgress =
            prior.read || prior.bookmark || prior.lastPageRead > 0;
        final cHasProgress = c.read || c.bookmark || c.lastPageRead > 0;
        if (cHasProgress && !priorHasProgress) existingByUrl[c.url] = c;
      }
    }

    // Delete rows that are duplicates (not the canonical row for their URL) or
    // whose URL is no longer in the source (Kotlin syncChaptersWithSource
    // removes chapters missing from the source). Only runs on a successful
    // full fetch — a failed fetch throws before reaching here, so chapters
    // aren't pruned on a transient error.
    final keepIds = {for (final c in existingByUrl.values) c.id};
    final toDelete = <int>[
      for (final c in existing)
        if (!keepIds.contains(c.id) || !sourceUrls.contains(c.url)) c.id,
    ];
    if (toDelete.isNotEmpty) {
      await (_db.delete(_db.chapters)..where((t) => t.id.isIn(toDelete))).go();
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // "Mark duplicate read chapter as read → After fetching new chapter"
    // (Kotlin MARK_DUPLICATE_CHAPTER_READ_NEW): a new chapter whose number
    // matches an already-read row is inserted read and left out of the
    // "new chapters" result so it doesn't spam the Updates tab.
    final sharedPrefs = await SharedPreferences.getInstance();
    final markDuplicateAsRead =
        (sharedPrefs.getStringList('mark_duplicate_read_chapter_read') ??
                const [])
            .contains('new');
    final readChapterNumbers = markDuplicateAsRead
        ? {
            for (final c in existing)
              if (c.read && c.chapterNumber >= 0) c.chapterNumber,
          }
        : const <double>{};
    final added = <Chapter>[];
    final updatedCompanions = <db.ChaptersCompanion>[];
    // New chapters are collected here and inserted in ONE batch below: the
    // first open of a long series is hundreds of new rows, and one INSERT each
    // is hundreds of DB round trips. `insertAll` can't return generated ids,
    // so `added` (which feeds the Updates tab / auto-download) is rebuilt from
    // a single re-query after the batch. Kept in fetched order via [newOrder].
    final newInserts = <db.ChaptersCompanion>[];
    final newOrder = <String>[];
    final newTemplates = <String, Chapter>{};
    final newExcluded = <String>{}; // inserted-read duplicates → not "new"
    // Source returns chapters in display order (typically newest first).
    // sourceOrder mirrors the index here so the existing ORDER BY
    // source_order in getChaptersByMangaId works.
    for (var i = 0; i < deduped.length; i++) {
      final s = deduped[i];
      final prior = existingByUrl[s.url];
      if (prior == null) {
        final duplicateRead = markDuplicateAsRead &&
            s.chapterNumber >= 0 &&
            readChapterNumbers.contains(s.chapterNumber);
        newTemplates[s.url] = Chapter(
          id: -1,
          mangaId: mangaId,
          read: duplicateRead,
          bookmark: false,
          lastPageRead: 0,
          dateFetch: nowMs,
          sourceOrder: i,
          url: s.url,
          name: s.name,
          dateUpload: s.dateUpload,
          chapterNumber: s.chapterNumber,
          scanlator: s.scanlator,
          lastModifiedAt: nowMs,
          version: 1,
          volumeNumber: s.volumeNumber,
        );
        newOrder.add(s.url);
        if (duplicateRead) newExcluded.add(s.url);
        newInserts.add(
          db.ChaptersCompanion.insert(
            mangaId: mangaId,
            url: s.url,
            name: s.name,
            scanlator: Value(s.scanlator),
            read: duplicateRead ? 1 : 0,
            bookmark: 0,
            lastPageRead: 0,
            chapterNumber: s.chapterNumber,
            sourceOrder: i,
            dateFetch: nowMs,
            dateUpload: s.dateUpload,
            lastModifiedAt: Value(nowMs),
            version: const Value(1),
            isSyncing: const Value(0),
            volumeNumber: Value(s.volumeNumber),
          ),
        );
      } else if (prior.name != s.name ||
          prior.scanlator != s.scanlator ||
          prior.chapterNumber != s.chapterNumber ||
          prior.sourceOrder != i ||
          prior.dateUpload != s.dateUpload ||
          prior.volumeNumber != s.volumeNumber) {
        // Only rows the source actually changed. A re-sync that finds nothing
        // new used to rewrite EVERY row regardless — 3,800 UPDATEs for a long
        // series, each firing the AFTER UPDATE trigger into a second write.
        // Cost aside, that trigger sets last_modified_at, which is what
        // cross-device sync reads to decide what changed: touching every
        // chapter on every library update told sync the whole series was
        // edited, every time.
        updatedCompanions.add(
          db.ChaptersCompanion(
            id: Value(prior.id),
            name: Value(s.name),
            scanlator: Value(s.scanlator),
            chapterNumber: Value(s.chapterNumber),
            sourceOrder: Value(i),
            dateUpload: Value(s.dateUpload),
            volumeNumber: Value(s.volumeNumber),
          ),
        );
      }
    }
    if (newInserts.isNotEmpty) {
      await _db.batch((b) => b.insertAll(_db.chapters, newInserts));
      // insertAll returns no ids — re-read just this batch's rows (every
      // insert above was stamped the same dateFetch=nowMs, which old rows
      // can't carry) and map url→id. Narrower than a full re-read (a sweep
      // adding 2 chapters to a 1500-row series shouldn't deserialize all
      // 1500) and still avoids a giant `url IN (…)` that would blow
      // SQLite's bound-variable limit on 1000+ chapter series.
      final newRows = await _db.customSelect(
        'SELECT _id, url FROM chapters WHERE manga_id = ?1 AND date_fetch = ?2',
        variables: [Variable<int>(mangaId), Variable<int>(nowMs)],
        readsFrom: {_db.chapters},
      ).get();
      final idByUrl = {
        for (final r in newRows) r.read<String>('url'): r.read<int>('_id'),
      };
      for (final url in newOrder) {
        if (newExcluded.contains(url)) continue;
        final id = idByUrl[url];
        if (id != null) added.add(newTemplates[url]!.copyWith(id: id));
      }
    }
    if (updatedCompanions.isNotEmpty) {
      await _db.batch((b) {
        for (final c in updatedCompanions) {
          b.update<db.Chapters, db.Chapter>(
            _db.chapters,
            c,
            where: (t) => t.id.equals(c.id.value),
          );
        }
      });
    }
    return added;
  }
}

final chapterRepositoryProvider = Provider<ChapterRepository>((ref) {
  return ChapterRepository(ref.watch(databaseProvider));
});
