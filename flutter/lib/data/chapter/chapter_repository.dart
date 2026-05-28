import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final existing = await getByMangaId(mangaId);
    final existingByUrl = {for (final c in existing) c.url: c};
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final added = <Chapter>[];
    final updatedCompanions = <db.ChaptersCompanion>[];
    // Source returns chapters in display order (typically newest first).
    // sourceOrder mirrors the index here so the existing ORDER BY
    // source_order in getChaptersByMangaId works.
    for (var i = 0; i < fetched.length; i++) {
      final s = fetched[i];
      final prior = existingByUrl[s.url];
      if (prior == null) {
        final inserted = Chapter(
          id: -1,
          mangaId: mangaId,
          read: false,
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
        final id = await _db.into(_db.chapters).insert(
              db.ChaptersCompanion.insert(
                mangaId: mangaId,
                url: s.url,
                name: s.name,
                scanlator: Value(s.scanlator),
                read: 0,
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
        added.add(inserted.copyWith(id: id));
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
