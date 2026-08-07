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
import '../../domain/manga/model/manga.dart';
import '../base/base_preferences.dart';
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
      // Defensive twin of the creator's filter: backups taken before that
      // filter existed still carry this device-local state, and replaying
      // it would repoint storage at another phone's SAF grant.
      if (p.key.startsWith(appStatePrefix)) continue;
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
  ///
  /// Two passes, as in Kotlin's `CategoriesRestorer`, because a category's
  /// `parent_id` is a LOCAL row id and a restored category does not keep the
  /// id it had on the device the backup came from. Writing the backup's raw
  /// parent id straight into the new row pointed each nested category at
  /// whatever local category happened to occupy that id — an unrelated
  /// category, itself, or nothing. (`_flattenHierarchy` tolerates all three
  /// rather than hanging, but a category caught in a cycle is unreachable
  /// from any root and disappears from the Categories screen.) So: insert
  /// top-level, learn each backup id's new local id, then set the parents.
  ///
  /// Order is likewise reassigned from the local maximum instead of being
  /// copied, so restored categories can't collide with the sort positions of
  /// categories already here; the backup's own order decides the sequence
  /// they are created in.
  Future<List<int>> _restoreCategories(List<BackupCategory> categories) async {
    if (categories.isEmpty) return const <int>[];
    final localCategories = await _categories.getAll();
    final byName = {for (final c in localCategories) c.name: c};
    var nextOrder = 0;
    for (final c in localCategories) {
      if (c.order >= nextOrder) nextOrder = c.order + 1;
    }

    // Backup id -> local id, for the parent remap. Ids are only trustworthy
    // as keys within one backup, never as local row ids.
    final liveIdByBackupId = <int, int>{};
    // Positional, so the returned list keeps the caller's index contract even
    // if a backup carries duplicate or defaulted category ids.
    final liveIdByIndex = List<int?>.filled(categories.length, null);

    final ordered = [
      for (var i = 0; i < categories.length; i++) (i, categories[i]),
    ]..sort((a, b) => a.$2.order.compareTo(b.$2.order));

    for (final (index, bc) in ordered) {
      final existing = byName[bc.name];
      if (existing != null) {
        liveIdByBackupId[bc.id] = existing.id;
        liveIdByIndex[index] = existing.id;
        continue;
      }
      final newId = await _categories.insert(
        name: bc.name,
        order: nextOrder++,
        flags: bc.flags,
        // Deliberately null: the parent may not exist yet, and its local id
        // isn't known until it does. Fixed up in the second pass.
        parentId: null,
      );
      liveIdByBackupId[bc.id] = newId;
      liveIdByIndex[index] = newId;
    }

    for (var i = 0; i < categories.length; i++) {
      final bc = categories[i];
      final liveId = liveIdByIndex[i];
      final backupParent = bc.parentId;
      if (liveId == null || backupParent == null) continue;
      final liveParent = liveIdByBackupId[backupParent];
      // A parent that isn't in this backup, or that resolves to the category
      // itself, stays top-level rather than becoming a dangling or self
      // reference.
      if (liveParent == null || liveParent == liveId) continue;
      await _categories.updateParent(id: liveId, parentId: liveParent);
    }

    return [for (final id in liveIdByIndex) id!];
  }

  /// Earliest KNOWN add-date wins; 0 means "unknown" on either side (e.g. a
  /// Kotlin-migrated row), never a candidate to keep over a real date. A
  /// brand-new entry with no date anywhere is stamped now.
  static int _mergeDateAdded(Manga? existing, int backupDateAdded, int nowMs) {
    final e = existing?.dateAdded ?? 0;
    final b = backupDateAdded;
    if (e == 0 && b == 0) return existing == null ? nowMs : 0;
    if (e == 0) return b;
    if (b == 0) return e;
    return e < b ? e : b;
  }

  /// Which side's favorite flag wins.
  ///
  /// Restoring an old backup over a live library must never un-favorite an
  /// entry the user added since it was taken, which is why this was a plain
  /// OR. But sync exchanges backups in BOTH directions, and under an OR a
  /// removal can never survive: the remote copy still says favorite, the
  /// merge flips it back, and that gets pushed as authoritative — so an
  /// un-favorite reappears on every device.
  ///
  /// `favoriteModifiedAt` is stamped by setFavorite for exactly this
  /// question. When both sides carry one, the newer stamp decides. Otherwise
  /// fall back to OR, which is what a backup predating the field needs.
  static bool _mergeFavorite(Manga? existing, BackupManga bm) {
    final incoming = bm.favoriteModifiedAt;
    final local = existing?.favoriteModifiedAt;
    if (incoming != null && local != null && incoming != local) {
      return incoming > local ? bm.favorite : existing!.favorite;
    }
    return bm.favorite || (existing?.favorite ?? false);
  }

  /// Keeps the later of the two stamps so the winning side's decision stays
  /// the one a later merge compares against. Overwriting with the incoming
  /// value unconditionally threw away a newer local decision.
  static int? _newerStamp(int? local, int? incoming) {
    if (local == null) return incoming;
    if (incoming == null) return local;
    return local > incoming ? local : incoming;
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
      favorite: _mergeFavorite(existing, bm) ? 1 : 0,
      // Keep the existing entry's update-scheduler state — zeroing it made
      // every restore discard learned fetch intervals and mark the whole
      // library due on the next sweep.
      lastUpdate: Value(existing?.lastUpdate ?? 0),
      nextUpdate: Value(existing?.nextUpdate ?? 0),
      initialized: bm.initialized ? 1 : 0,
      viewer: bm.viewer,
      chapterFlags: bm.chapterFlags,
      // Keep the local custom-cover stamp — zeroing it invalidated an
      // existing entry's edited cover on every restore.
      coverLastModified: existing?.coverLastModified ?? 0,
      dateAdded: _mergeDateAdded(existing, bm.dateAdded, nowMs),
      updateStrategy: Value(
        UpdateStrategy.values
            .elementAt(
              bm.updateStrategy.clamp(0, UpdateStrategy.values.length - 1),
            )
            .dbValue,
      ),
      calculateInterval: Value(existing?.fetchInterval ?? 0),
      lastModifiedAt: Value(bm.lastModifiedAt == 0 ? nowMs : bm.lastModifiedAt),
      favoriteModifiedAt: Value(
        _newerStamp(existing?.favoriteModifiedAt, bm.favoriteModifiedAt),
      ),
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
          // When local state won (or was merged), keep the LOCAL stamp too:
          // writing the backup's older stamp alongside preserved-local values
          // made the SECOND restore of the same backup see "equal stamps →
          // backup wins" and un-read what the first pass kept. Restores must
          // be idempotent.
          lastModifiedAt: Value(
            useLocal || merge ? prior.lastModifiedAt : bc.lastModifiedAt,
          ),
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
      final chapterIdByUrl = await _chapters.chapterIdsByUrl(mangaId);
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
