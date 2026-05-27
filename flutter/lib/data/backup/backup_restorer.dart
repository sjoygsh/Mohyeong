/// Reads a decoded [Backup] back into the local Drift database.
///
/// Mirrors `eu.kanade.tachiyomi.data.backup.restore.BackupRestorer` in
/// Mihon: every manga is upserted by (source, url); chapters are merged
/// preserving any newer local state; history/tracking/categories are
/// re-attached. Restore is additive — existing library entries that
/// aren't mentioned in the backup are left alone.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/manga/model/update_strategy.dart';
import '../../domain/track/model/track.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import '../history/history_repository.dart';
import '../manga/manga_repository.dart';
import '../source/source_repository.dart';
import '../track/track_repository.dart';
import 'models/backup_models.dart';

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.mangaRestored,
    required this.categoriesRestored,
    required this.extensionReposRestored,
    required this.preferencesRestored,
    required this.skippedMangaWithoutSource,
  });

  final int mangaRestored;
  final int categoriesRestored;
  final int extensionReposRestored;
  final int preferencesRestored;

  /// Mihon backups can reference sources whose extension isn't installed
  /// in this app. The manga row is still restored (the library shows a
  /// "source unavailable" placeholder), so this is informational only.
  final int skippedMangaWithoutSource;
}

class BackupRestorer {
  BackupRestorer({
    required db.AppDatabase database,
    required MangaRepository mangaRepository,
    required ChapterRepository chapterRepository,
    required CategoryRepository categoryRepository,
    required HistoryRepository historyRepository,
    required TrackRepository trackRepository,
    required SourceRepository sourceRepository,
  })  : _db = database,
        _manga = mangaRepository,
        _chapters = chapterRepository,
        _categories = categoryRepository,
        _history = historyRepository,
        _tracks = trackRepository,
        _sources = sourceRepository;

  final db.AppDatabase _db;
  final MangaRepository _manga;
  final ChapterRepository _chapters;
  final CategoryRepository _categories;
  final HistoryRepository _history;
  final TrackRepository _tracks;
  final SourceRepository _sources;

  Future<BackupRestoreResult> restore(Backup backup) async {
    var mangaCount = 0;
    var skipped = 0;

    final restoredCategoryIds = await _restoreCategories(backup.backupCategories);

    for (final s in backup.backupSources) {
      await _sources.upsert(id: s.sourceId, lang: '', name: s.name);
    }

    for (final bm in backup.backupManga) {
      try {
        await _restoreManga(bm, restoredCategoryIds);
        mangaCount += 1;
      } catch (_) {
        // Best-effort: a single corrupt entry shouldn't abort the restore.
        skipped += 1;
      }
    }

    var repoCount = 0;
    for (final r in backup.backupExtensionRepo) {
      await _db.upsertRepo(
        r.baseUrl,
        r.name,
        r.shortName.isEmpty ? null : r.shortName,
        r.website,
        r.signingKeyFingerprint,
      );
      repoCount += 1;
    }

    final prefCount = await _restorePreferences(backup.backupPreferences);

    return BackupRestoreResult(
      mangaRestored: mangaCount,
      categoriesRestored: restoredCategoryIds.length,
      extensionReposRestored: repoCount,
      preferencesRestored: prefCount,
      skippedMangaWithoutSource: skipped,
    );
  }

  /// Replays each [BackupPreference] back into [SharedPreferences].
  /// Existing values are overwritten — backups are treated as the
  /// source of truth for app-level settings. Per-source preferences are
  /// intentionally not restored: they live in the JS extensions that
  /// haven't shipped yet.
  Future<int> _restorePreferences(List<BackupPreference> prefs) async {
    if (prefs.isEmpty) return 0;
    final store = await SharedPreferences.getInstance();
    var count = 0;
    for (final p in prefs) {
      final value = p.value;
      final ok = switch (value) {
        BooleanPreferenceValue() => await store.setBool(p.key, value.value),
        // SharedPreferences only has int / double — Long and Int collapse
        // onto setInt. Floats land in setDouble. JS-side Mihon int values
        // never exceed Dart's safe range so this is a no-op narrowing.
        IntPreferenceValue() => await store.setInt(p.key, value.value),
        LongPreferenceValue() => await store.setInt(p.key, value.value),
        FloatPreferenceValue() => await store.setDouble(p.key, value.value),
        StringPreferenceValue() => await store.setString(p.key, value.value),
        StringSetPreferenceValue() =>
          await store.setStringList(p.key, value.value.toList()),
      };
      if (ok) count += 1;
    }
    return count;
  }

  /// Restore categories, returning a list of local IDs in the same order
  /// as the input. Existing categories (matched by name) are reused.
  Future<List<int>> _restoreCategories(List<BackupCategory> categories) async {
    final localCategories = await _categories.getAll();
    final byName = {for (final c in localCategories) c.name: c};
    final restoredIds = <int>[];
    for (final bc in categories) {
      final existing = byName[bc.name];
      if (existing != null) {
        restoredIds.add(existing.id);
        continue;
      }
      final newId = await _categories.insert(
        name: bc.name,
        order: bc.order,
        flags: bc.flags,
        parentId: bc.parentId,
      );
      restoredIds.add(newId);
    }
    return restoredIds;
  }

  Future<void> _restoreManga(
    BackupManga bm,
    List<int> categoryIdByIndex,
  ) async {
    final existing = await _manga.getByUrlAndSource(bm.url, bm.source);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final companion = db.MangasCompanion.insert(
      id: existing == null ? const Value.absent() : Value(existing.id),
      source: bm.source,
      url: bm.url,
      title: bm.title,
      artist: Value(bm.artist),
      author: Value(bm.author),
      description: Value(bm.description),
      // Mapper writes genre as comma-joined without spaces; match that.
      genre: Value(bm.genre.isEmpty ? null : bm.genre.join(',')),
      status: bm.status,
      thumbnailUrl: Value(bm.thumbnailUrl),
      favorite: bm.favorite ? 1 : 0,
      lastUpdate: const Value(0),
      nextUpdate: const Value(0),
      initialized: bm.initialized ? 1 : 0,
      viewer: bm.viewer,
      chapterFlags: bm.chapterFlags,
      coverLastModified: 0,
      dateAdded: bm.dateAdded == 0 ? nowMs : bm.dateAdded,
      updateStrategy: Value(
        UpdateStrategy.values
            .elementAt(
              bm.updateStrategy.clamp(0, UpdateStrategy.values.length - 1),
            )
            .dbValue,
      ),
      calculateInterval: const Value(0),
      lastModifiedAt: Value(bm.lastModifiedAt == 0 ? nowMs : bm.lastModifiedAt),
      favoriteModifiedAt: Value(bm.favoriteModifiedAt),
      version: Value(bm.version),
      isSyncing: const Value(0),
      notes: Value(bm.notes),
    );

    final int mangaId;
    if (existing == null) {
      mangaId = await _db.into(_db.mangas).insertOnConflictUpdate(companion);
    } else {
      mangaId = existing.id;
      await (_db.update(_db.mangas)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }

    // Chapters — merge by URL.
    final localChapters = await _chapters.getByMangaId(mangaId);
    final localByUrl = {for (final c in localChapters) c.url: c};
    for (final bc in bm.chapters) {
      final prior = localByUrl[bc.url];
      final useLocal = prior != null &&
          bc.lastModifiedAt != 0 &&
          prior.lastModifiedAt > bc.lastModifiedAt;

      await _db.into(_db.chapters).insertOnConflictUpdate(
            db.ChaptersCompanion.insert(
              id: prior == null ? const Value.absent() : Value(prior.id),
              mangaId: mangaId,
              url: bc.url,
              name: bc.name,
              scanlator: Value(bc.scanlator),
              read: (useLocal ? prior.read : bc.read) ? 1 : 0,
              bookmark: (useLocal ? prior.bookmark : bc.bookmark) ? 1 : 0,
              lastPageRead: useLocal ? prior.lastPageRead : bc.lastPageRead,
              chapterNumber: bc.chapterNumber,
              sourceOrder: bc.sourceOrder,
              dateFetch: bc.dateFetch,
              dateUpload: bc.dateUpload,
              lastModifiedAt: Value(bc.lastModifiedAt),
              version: Value(bc.version),
              isSyncing: const Value(0),
              bookmarkNote:
                  Value(bc.bookmarkNote.isEmpty ? null : bc.bookmarkNote),
              volumeNumber: Value(bc.volumeNumber),
            ),
          );
    }

    // History rows reference chapters by URL on the wire — resolve to
    // local chapter IDs now that chapters are in place.
    final refreshedChapters = await _chapters.getByMangaId(mangaId);
    final chapterIdByUrl = {for (final c in refreshedChapters) c.url: c.id};
    for (final h in bm.history) {
      final chapterId = chapterIdByUrl[h.url];
      if (chapterId == null) continue;
      await _history.upsert(
        chapterId: chapterId,
        readAt: h.lastRead == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(h.lastRead),
        timeReadMs: h.readDuration,
      );
    }

    for (final t in bm.tracking) {
      await _tracks.upsert(Track(
        id: -1,
        mangaId: mangaId,
        trackerId: t.syncId,
        remoteId: t.mediaId,
        libraryId: t.libraryId,
        title: t.title,
        lastChapterRead: t.lastChapterRead,
        totalChapters: t.totalChapters,
        status: t.status,
        score: t.score,
        remoteUrl: t.trackingUrl,
        startDate: t.startedReadingDate,
        finishDate: t.finishedReadingDate,
        private: t.private,
      ));
    }

    final categoryIds = <int>{};
    for (final idx in bm.categories) {
      if (idx < 0 || idx >= categoryIdByIndex.length) continue;
      categoryIds.add(categoryIdByIndex[idx]);
    }
    if (categoryIds.isNotEmpty) {
      await _categories.setCategoriesForManga(mangaId, categoryIds);
    }
  }
}

final backupRestorerProvider = Provider<BackupRestorer>((ref) {
  return BackupRestorer(
    database: ref.watch(databaseProvider),
    mangaRepository: ref.watch(mangaRepositoryProvider),
    chapterRepository: ref.watch(chapterRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
    historyRepository: ref.watch(historyRepositoryProvider),
    trackRepository: ref.watch(trackRepositoryProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
  );
});
