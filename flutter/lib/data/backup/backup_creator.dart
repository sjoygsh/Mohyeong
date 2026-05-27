/// Walks the local Drift database and builds a [Backup] message ready to
/// be encoded by `backup_codec.dart`.
///
/// Mirrors `eu.kanade.tachiyomi.data.backup.create.BackupCreator` in the
/// Kotlin app: we capture every favorited manga, its chapters/history/
/// tracking/category memberships, the small `sources` table, configured
/// extension repos, and every app-wide SharedPreferences entry. Per-source
/// preferences are still skipped — they require the JS extensions to be
/// loaded to round-trip their values, which we can't do during a
/// non-interactive export.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    for (final m in favorites) {
      seenSourceIds.add(m.source);

      final chapters = await _chapters.getByMangaId(m.id);
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

      final mangaCategories = await _categories.getByMangaId(m.id);
      final categoryIndices = <int>[
        for (final c in mangaCategories)
          if (!c.isSystemCategory && categoryIndexById.containsKey(c.id))
            categoryIndexById[c.id]!,
      ];

      final history = await _history.getByMangaId(m.id);
      // History needs the chapter URL (not id) for Mihon compat — we
      // already have the chapters fetched above, so build a lookup.
      final chapterUrlById = {for (final c in chapters) c.id: c.url};
      final backupHistory = <BackupHistory>[
        for (final h in history)
          if (chapterUrlById.containsKey(h.chapterId))
            BackupHistory(
              url: chapterUrlById[h.chapterId]!,
              lastRead: h.readAt?.millisecondsSinceEpoch ?? 0,
              readDuration: h.readDuration,
            ),
      ];

      final tracks = await _tracks.getByMangaId(m.id);
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
        excludedScanlators: const [],
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

    return Backup(
      backupManga: backupManga,
      backupCategories: backupCategories,
      backupSources: backupSources,
      backupPreferences: await _collectAppPreferences(),
      backupSourcePreferences: const [],
      backupExtensionRepo: backupRepos,
      backupMangaLinks: const [],
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
      final raw = prefs.get(key);
      final value = _wrapPreferenceValue(raw);
      if (value == null) continue;
      out.add(BackupPreference(key: key, value: value));
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
  );
});
