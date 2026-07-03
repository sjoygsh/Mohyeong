/// Reads a decoded [Backup] back into the local Drift database.
///
/// Mirrors `eu.kanade.tachiyomi.data.backup.restore.BackupRestorer` in
/// Mihon: every manga is upserted by (source, url); chapters are merged
/// preserving any newer local state; history/tracking/categories are
/// re-attached. Restore is additive — existing library entries that
/// aren't mentioned in the backup are left alone.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../manga/excluded_scanlators_repository.dart';
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
    required this.linksRestored,
    required this.skippedMangaWithoutSource,
  });

  final int mangaRestored;
  final int categoriesRestored;
  final int extensionReposRestored;
  final int preferencesRestored;
  final int linksRestored;

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
    required ExcludedScanlatorsRepository excludedScanlatorsRepository,
  })  : _db = database,
        _manga = mangaRepository,
        _chapters = chapterRepository,
        _categories = categoryRepository,
        _history = historyRepository,
        _tracks = trackRepository,
        _sources = sourceRepository,
        _excludedScanlators = excludedScanlatorsRepository;

  final db.AppDatabase _db;
  final MangaRepository _manga;
  final ChapterRepository _chapters;
  final CategoryRepository _categories;
  final HistoryRepository _history;
  final TrackRepository _tracks;
  final SourceRepository _sources;
  final ExcludedScanlatorsRepository _excludedScanlators;

  Future<BackupRestoreResult> restore(Backup backup) async {
    var mangaCount = 0;
    var skipped = 0;

    final restoredCategoryIds = await _restoreCategories(backup.backupCategories);

    for (final s in backup.backupSources) {
      await _sources.upsert(id: s.sourceId, lang: '', name: s.name);
    }

    for (final bm in backup.backupManga) {
      try {
        // One transaction per manga: keeps a mid-restore failure from
        // leaving that entry half-written (manga row without its chapters)
        // and collapses its dozens of writes into one fsync.
        await _db.transaction(() => _restoreManga(bm, restoredCategoryIds));
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
    await _restoreSourcePreferences(backup.backupSourcePreferences);
    final linkCount = await _restoreLinks(backup.backupMangaLinks);

    return BackupRestoreResult(
      mangaRestored: mangaCount,
      categoriesRestored: restoredCategoryIds.length,
      extensionReposRestored: repoCount,
      preferencesRestored: prefCount,
      linksRestored: linkCount,
      skippedMangaWithoutSource: skipped,
    );
  }

  /// Re-creates the manga_links cluster table from the backup. Skips any
  /// link whose primary or linked manga isn't present in the local DB —
  /// happens when a backup references manga the user has since removed.
  Future<int> _restoreLinks(List<BackupMangaLink> links) async {
    if (links.isEmpty) return 0;
    var count = 0;
    for (final l in links) {
      final primary = await _manga.getByUrlAndSource(l.primaryUrl, l.primarySource);
      if (primary == null) continue;
      final linked = await _manga.getByUrlAndSource(l.linkedUrl, l.linkedSource);
      if (linked == null) continue;
      await _db.insertLink(primary.id, linked.id, l.priority);
      count += 1;
    }
    return count;
  }

  /// Replays each [BackupPreference] back into [SharedPreferences].
  /// Existing values are overwritten — backups are treated as the
  /// source of truth for app-level settings. Per-source extension settings ARE
  /// restored (see _restoreSourcePreferences): they live in the JS extensions that
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

  /// Writes each backed-up per-source settings map back to its
  /// `source_prefs_<sourceKey>` JSON blob. The live runtimes pick the
  /// values up on next load (sources aren't usually running mid-restore).
  /// Kotlin-made backups key these by APK package name, which won't match
  /// a JS extension slug — those entries are restored verbatim and simply
  /// never read, which is the same best-effort Kotlin applies in reverse.
  Future<void> _restoreSourcePreferences(
    List<BackupSourcePreferences> sourcePrefs,
  ) async {
    if (sourcePrefs.isEmpty) return;
    final store = await SharedPreferences.getInstance();
    for (final sp in sourcePrefs) {
      final map = <String, String>{
        for (final p in sp.prefs)
          if (p.value is StringPreferenceValue)
            p.key: (p.value as StringPreferenceValue).value,
      };
      if (map.isEmpty) continue;
      await store.setString(
        'source_prefs_${sp.sourceKey}',
        jsonEncode(map),
      );
    }
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
      // OR with the local flag (Mihon parity): restoring an old backup over
      // a live library must never UN-favorite an entry the user added since
      // the backup was taken.
      favorite: (bm.favorite || (existing?.favorite ?? false)) ? 1 : 0,
      lastUpdate: const Value(0),
      nextUpdate: const Value(0),
      initialized: bm.initialized ? 1 : 0,
      viewer: bm.viewer,
      chapterFlags: bm.chapterFlags,
      // Keep the local custom-cover stamp — zeroing it invalidated an
      // existing entry's edited cover on every restore.
      coverLastModified: existing?.coverLastModified ?? 0,
      // Earliest nonzero add-date wins; the add date shouldn't move because
      // a backup was replayed.
      dateAdded: existing == null
          ? (bm.dateAdded == 0 ? nowMs : bm.dateAdded)
          : (bm.dateAdded == 0 || existing.dateAdded < bm.dateAdded
              ? existing.dateAdded
              : bm.dateAdded),
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
      // Don't blank local notes with a backup that never had any.
      notes: Value(bm.notes.isEmpty ? (existing?.notes ?? '') : bm.notes),
    );

    final int mangaId;
    if (existing == null) {
      mangaId = await _db.into(_db.mangas).insertOnConflictUpdate(companion);
    } else {
      mangaId = existing.id;
      await (_db.update(_db.mangas)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    }

    // Chapters — merge by URL. Local state wins when it's provably newer;
    // when the backup predates lastModifiedAt stamping (0) the two can't be
    // ordered, so merge progress like Mihon does (OR the flags, max the
    // page) instead of letting an old backup un-read local chapters. All
    // rows land in ONE batch — per-row upserts made a large restore
    // thousands of sequential round trips.
    final localChapters = await _chapters.getByMangaId(mangaId);
    final localByUrl = {for (final c in localChapters) c.url: c};
    final chapterRows = <db.ChaptersCompanion>[];
    for (final bc in bm.chapters) {
      final prior = localByUrl[bc.url];
      final useLocal = prior != null &&
          bc.lastModifiedAt != 0 &&
          prior.lastModifiedAt > bc.lastModifiedAt;
      final merge = prior != null && bc.lastModifiedAt == 0;
      final read = useLocal
          ? prior.read
          : (merge ? (prior.read || bc.read) : bc.read);
      final bookmark = useLocal
          ? prior.bookmark
          : (merge ? (prior.bookmark || bc.bookmark) : bc.bookmark);
      final lastPageRead = useLocal
          ? prior.lastPageRead
          : (merge
              ? (prior.lastPageRead > bc.lastPageRead
                  ? prior.lastPageRead
                  : bc.lastPageRead)
              : bc.lastPageRead);

      chapterRows.add(
        db.ChaptersCompanion.insert(
          id: prior == null ? const Value.absent() : Value(prior.id),
          mangaId: mangaId,
          url: bc.url,
          name: bc.name,
          scanlator: Value(bc.scanlator),
          read: read ? 1 : 0,
          bookmark: bookmark ? 1 : 0,
          lastPageRead: lastPageRead,
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
    if (chapterRows.isNotEmpty) {
      await _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.chapters, chapterRows),
      );
    }

    // History rows reference chapters by URL on the wire — resolve to
    // local chapter IDs now that chapters are in place. The re-read only
    // pays off when there IS history (most entries have none), and only the
    // just-inserted chapters need fresh ids — existing ones are in
    // [localByUrl] already.
    if (bm.history.isNotEmpty) {
      final refreshedChapters = await _chapters.getByMangaId(mangaId);
      final chapterIdByUrl = {for (final c in refreshedChapters) c.url: c.id};
      for (final h in bm.history) {
        final chapterId = chapterIdByUrl[h.url];
        if (chapterId == null) continue;
        // Absolute (max) write, not additive — re-applying a backup or the
        // sync restore-then-push cycle must not keep accumulating read time.
        await _history.upsertAbsolute(
          chapterId: chapterId,
          readAtMs: h.lastRead == 0 ? null : h.lastRead,
          timeReadMs: h.readDuration,
        );
      }
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

    // Excluded scanlators — previously ignored on import (consensus-review
    // data-loss finding): the codec parses them, write them back.
    if (bm.excludedScanlators.isNotEmpty) {
      await _excludedScanlators.setForManga(
        mangaId,
        bm.excludedScanlators.toSet(),
      );
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
    excludedScanlatorsRepository:
        ref.watch(excludedScanlatorsRepositoryProvider),
  );
});
