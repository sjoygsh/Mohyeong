import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/chapter/model/chapter.dart';
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

  /// Bulk-set the read flag for every chapter belonging to [mangaId].
  /// When marking unread, also resets `last_page_read` to 0 so the
  /// reader doesn't jump to a now-meaningless position. Used by the
  /// library multi-select "mark all read/unread" action.
  Future<void> setReadForManga(int mangaId, bool read) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.chapters)..where((t) => t.mangaId.equals(mangaId)))
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
  Future<List<Chapter>> syncChaptersWithSource(
    int mangaId,
    List<SourceChapter> fetched,
  ) async {
    if (fetched.isEmpty) return const [];
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
      } else {
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
      // insertAll returns no ids — re-read the manga's rows once (chapters are
      // unique per (manga, url), and duplicates were already pruned above) and
      // map url→id. A full re-query avoids a giant `url IN (…)` that would blow
      // SQLite's bound-variable limit on 1000+ chapter series.
      final idByUrl = {for (final c in await getByMangaId(mangaId)) c.url: c.id};
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
