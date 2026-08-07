/// Walks the local Drift database and builds a [Backup] message ready to
/// be encoded by `backup_codec.dart`.
///
/// Mirrors `eu.kanade.tachiyomi.data.backup.create.BackupCreator` in the
/// Kotlin app: we capture every favorited manga, its chapters/history/
/// tracking/category memberships, the small `sources` table, configured
/// extension repos, every app-wide SharedPreferences entry, per-manga
/// excluded scanlators, and per-source extension settings
/// (backupSourcePreferences, from the `source_prefs_<slug>` JSON maps —
/// no JS runtime needed since the host owns the store).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../manga/excluded_scanlators_repository.dart';
import '../manga/scanlator_priority_repository.dart';
import '../base/base_preferences.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import '../history/history_repository.dart';
import '../manga/manga_repository.dart';
import '../source/source_repository.dart';
import '../track/track_repository.dart';
import 'models/backup_models.dart';

class BackupCreator {
  BackupCreator({
    required db.AppDatabase database,
    required MangaRepository mangaRepository,
    required ChapterRepository chapterRepository,
    required CategoryRepository categoryRepository,
    required HistoryRepository historyRepository,
    required TrackRepository trackRepository,
    required SourceRepository sourceRepository,
    required ExcludedScanlatorsRepository excludedScanlatorsRepository,
    required ScanlatorPriorityRepository scanlatorPriorityRepository,
  })  : _db = database,
        _manga = mangaRepository,
        _chapters = chapterRepository,
        _categories = categoryRepository,
        _history = historyRepository,
        _tracks = trackRepository,
        _sources = sourceRepository,
        _excludedScanlators = excludedScanlatorsRepository,
        _scanlatorPriority = scanlatorPriorityRepository;

  final db.AppDatabase _db;
  final MangaRepository _manga;
  final ChapterRepository _chapters;
  final CategoryRepository _categories;
  final HistoryRepository _history;
  final TrackRepository _tracks;
  final SourceRepository _sources;
  final ExcludedScanlatorsRepository _excludedScanlators;
  final ScanlatorPriorityRepository _scanlatorPriority;

  /// Snapshots the library into a [Backup]. Streams nothing — the caller
  /// is expected to wrap this in a progress indicator if needed; Mihon's
  /// own creator also runs synchronously inside a coroutine.
  Future<Backup> create() async {
    // Categories first — manga need indices into the resulting list.
    final allCategories = await _categories.getAll();
    final exportedCategories = allCategories
        .where((c) => !c.isSystemCategory)
        .toList(growable: false);

    final backupCategories = exportedCategories
        .map((c) => BackupCategory(
              name: c.name,
              order: c.order,
              id: c.id,
              flags: c.flags,
              parentId: c.parentId,
            ))
        .toList(growable: false);

    // Build a `categoryId -> exported index` map so per-manga membership
    // can be written as protobuf int indices the way Mihon expects.
    final categoryIndexById = <int, int>{
      for (var i = 0; i < exportedCategories.length; i++)
        exportedCategories[i].id: i,
    };

    final favorites = await _manga.getFavorites();
    final backupManga = <BackupManga>[];
    final seenSourceIds = <int>{};

    // Everything the per-manga body needs, fetched in one query each rather
    // than five per favourite. Sync calls create() on every cycle, so at a
    // few hundred favourites that loop was over a thousand round trips.
    final favoriteIds = favorites.map((m) => m.id).toList(growable: false);
    final chaptersByManga = await _chapters.getByMangaIds(favoriteIds);
    final categoryIdsByManga =
        await _categories.categoryIdsByMangaIds(favoriteIds);
    final historyByManga = await _history.getByMangaIds(favoriteIds);
    final tracksByManga = await _tracks.getByMangaIds(favoriteIds);
    final excludedByManga = await _excludedScanlators.getByMangaIds(
      favoriteIds,
    );
    final priorityByManga = await _scanlatorPriority.getByMangaIds(favoriteIds);

    for (final m in favorites) {
      seenSourceIds.add(m.source);

      final chapters = chaptersByManga[m.id] ?? const [];
      final backupChapters = chapters
          .map((c) => BackupChapter(
                url: c.url,
                name: c.name,
                scanlator: c.scanlator,
                read: c.read,
                bookmark: c.bookmark,
                lastPageRead: c.lastPageRead,
                dateFetch: c.dateFetch,
                dateUpload: c.dateUpload,
                chapterNumber: c.chapterNumber,
                sourceOrder: c.sourceOrder,
                lastModifiedAt: c.lastModifiedAt,
                version: c.version,
                bookmarkNote: c.bookmarkNote ?? '',
                volumeNumber: c.volumeNumber,
              ))
          .toList(growable: false);

      // `categoryIndexById` already excludes the system category, so the
      // membership ids alone answer this — no join back to `categories`.
      final categoryIndices = <int>[
        for (final id in categoryIdsByManga[m.id] ?? const <int>[])
          if (categoryIndexById.containsKey(id)) categoryIndexById[id]!,
      ];

      final history = historyByManga[m.id] ?? const [];
      // History needs the chapter URL (not id) for Mihon compat — we
      // already have the chapters fetched above, so build a lookup.
      final chapterUrlById = {for (final c in chapters) c.id: c.url};
      final backupHistory = <BackupHistory>[
        for (final h in history)
          if (chapterUrlById.containsKey(h.chapterId))
            BackupHistory(
              url: chapterUrlById[h.chapterId]!,
              lastRead: h.readAt?.millisecondsSinceEpoch ?? 0,
              // Milliseconds, same unit as Kotlin BackupHistory.readDuration
      // (verified against MangaBackupCreator).
      readDuration: h.readDuration,
            ),
      ];

      final tracks = tracksByManga[m.id] ?? const [];
      final backupTracks = tracks
          .map((t) => BackupTracking(
                syncId: t.trackerId,
                libraryId: t.libraryId,
                trackingUrl: t.remoteUrl,
                title: t.title,
                lastChapterRead: t.lastChapterRead,
                totalChapters: t.totalChapters,
                score: t.score,
                status: t.status,
                startedReadingDate: t.startDate,
                finishedReadingDate: t.finishDate,
                private: t.private,
                mediaId: t.remoteId,
              ))
          .toList(growable: false);

      backupManga.add(BackupManga(
        source: m.source,
        url: m.url,
        title: m.title,
        artist: m.artist,
        author: m.author,
        description: m.description,
        genre: m.genre ?? const [],
        status: m.status,
        thumbnailUrl: m.thumbnailUrl,
        dateAdded: m.dateAdded,
        viewer: m.viewerFlags,
        chapters: backupChapters,
        categories: categoryIndices,
        tracking: backupTracks,
        favorite: m.favorite,
        chapterFlags: m.chapterFlags,
        // viewerFlags is duplicated in tag 14 and 102 in Mihon for legacy
        // reasons; emit null on tag 102 so older Mihon reads tag 14.
        viewerFlags: null,
        history: backupHistory,
        updateStrategy: m.updateStrategy.dbValue,
        lastModifiedAt: m.lastModifiedAt,
        favoriteModifiedAt: m.favoriteModifiedAt,
        // Was hardcoded empty — per-manga scanlator exclusions silently
        // vanished on every export (consensus-review data-loss finding).
        excludedScanlators:
            (excludedByManga[m.id] ?? const <String>{}).toList(),
        // The per-manga scanlator RANKING. Neither app backed this up, so a
        // ranking was lost on every export — the same data-loss class as the
        // exclusions above, one table over.
        scanlatorPriority: priorityByManga[m.id] ?? const <String>[],
        version: m.version,
        notes: m.notes,
        initialized: m.initialized,
      ));
    }

    // `sources` table — only emit entries actually referenced by the
    // exported manga, matching Mihon's behavior.
    final allSources = await _sources.getAll();
    final backupSources = <BackupSource>[
      for (final s in allSources)
        if (seenSourceIds.contains(s.id))
          BackupSource(name: s.name, sourceId: s.id),
    ];

    // Extension repos — copy verbatim from the table.
    final repoRows = await _db.findAllRepos().get();
    final backupRepos = repoRows
        .map((r) => BackupExtensionRepos(
              baseUrl: r.baseUrl,
              name: r.name,
              shortName: r.shortName ?? '',
              website: r.website,
              signingKeyFingerprint: r.signingKeyFingerprint,
            ))
        .toList(growable: false);

    // Cross-source links — dump the manga_links cluster table verbatim,
    // keyed by the source+url pair so the linked side can be re-resolved
    // on restore even if local manga ids have shifted.
    final linkRows = await _db.getAllLinksForBackup().get();
    final backupLinks = linkRows
        .map((r) => BackupMangaLink(
              primarySource: r.primarySource,
              primaryUrl: r.primaryUrl,
              linkedSource: r.linkedSource,
              linkedUrl: r.linkedUrl,
              priority: r.priority,
            ))
        .toList(growable: false);

    return Backup(
      backupManga: backupManga,
      backupCategories: backupCategories,
      backupSources: backupSources,
      backupPreferences: await _collectAppPreferences(),
      backupSourcePreferences: await _collectSourcePreferences(),
      backupExtensionRepo: backupRepos,
      backupMangaLinks: backupLinks,
    );
  }

  /// Dumps every SharedPreferences key/value into a list of
  /// [BackupPreference]s. Types are detected by probing each getter — the
  /// type-detection mirrors how `shared_preferences` stores them, so
  /// `getBool` is checked before `getInt`/`getDouble` to avoid false
  /// positives on `0`/`1` integer values that happen to be stored as bools.
  ///
  /// Unknown / ambiguous types fall through to a `StringPreferenceValue`
  /// holding the stringified representation, which keeps the round-trip
  /// lossless for our own app even if the type is opaque.
  Future<List<BackupPreference>> _collectAppPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final out = <BackupPreference>[];
    for (final key in keys) {
      // Per-source extension settings ride in backupSourcePreferences
      // (Kotlin parity) — keep them out of the app-level dump so they
      // aren't stored twice.
      if (key.startsWith('source_prefs_')) continue;
      // Mihon's `appStateKey()` marks a pref as THIS DEVICE's state, not a
      // user setting, and excludes it from backups. Carrying them across
      // would restore another device's SAF storage grant, its
      // onboarding-complete flag, or its downloaded-only mode onto a phone
      // where none of that is true.
      if (key.startsWith(appStatePrefix)) continue;
      final raw = prefs.get(key);
      final value = _wrapPreferenceValue(raw);
      if (value == null) continue;
      out.add(BackupPreference(key: key, value: value));
    }
    return out;
  }

  /// Per-source extension settings (the JSON maps stored under
  /// `source_prefs_<slug>`) as Kotlin-shaped BackupSourcePreferences:
  /// sourceKey = the extension slug, prefs = string entries. Cross-app
  /// compatibility with Kotlin builds is best-effort only — Kotlin keys its
  /// stores by APK package name, which doesn't exist in the JS model.
  Future<List<BackupSourcePreferences>> _collectSourcePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <BackupSourcePreferences>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('source_prefs_')) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      out.add(BackupSourcePreferences(
        sourceKey: key.substring('source_prefs_'.length),
        prefs: [
          for (final e in decoded.entries)
            BackupPreference(
              key: e.key,
              value: StringPreferenceValue(e.value.toString()),
            ),
        ],
      ));
    }
    return out;
  }

  /// Maps a raw [SharedPreferences.get] result onto a
  /// [BackupPreferenceValue]. Returns null if the value can't be encoded
  /// (e.g. an unsupported runtime type slipped in via a platform plugin).
  BackupPreferenceValue? _wrapPreferenceValue(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return BooleanPreferenceValue(raw);
    if (raw is int) return LongPreferenceValue(raw);
    if (raw is double) return FloatPreferenceValue(raw);
    if (raw is String) return StringPreferenceValue(raw);
    if (raw is List<String>) return StringSetPreferenceValue(raw.toSet());
    if (raw is List && raw.every((e) => e is String)) {
      return StringSetPreferenceValue(raw.cast<String>().toSet());
    }
    return null;
  }
}

final backupCreatorProvider = Provider<BackupCreator>((ref) {
  return BackupCreator(
    database: ref.watch(databaseProvider),
    mangaRepository: ref.watch(mangaRepositoryProvider),
    chapterRepository: ref.watch(chapterRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
    historyRepository: ref.watch(historyRepositoryProvider),
    trackRepository: ref.watch(trackRepositoryProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
    excludedScanlatorsRepository:
        ref.watch(excludedScanlatorsRepositoryProvider),
    scanlatorPriorityRepository:
        ref.watch(scanlatorPriorityRepositoryProvider),
  );
});
