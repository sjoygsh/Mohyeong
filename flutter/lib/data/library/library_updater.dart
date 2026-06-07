import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/chapter/interactor/filter_chapters_for_download.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/interactor/fetch_interval.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/update_strategy.dart';
import '../../domain/source/model/source_manga.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../download/download_repository.dart';
import '../manga/manga_repository.dart';
import '../source/extension_repository.dart';
import 'library_update_preference.dart';

/// Domain service that fetches the latest chapter list for every manga in
/// the user's library and reconciles it against the persisted state.
/// Equivalent to the Kotlin `LibraryUpdateJob.updateChapterList` flow.
///
/// Update strategy obeys [Manga.updateStrategy]:
///   * `alwaysUpdate` — included.
///   * `onlyFetchOnce` — skipped (manual-only sources).
///
/// Errors talking to a source are caught per-manga and surfaced via
/// [LibraryUpdateResult.failures]; one bad source must not prevent the rest
/// of the library from updating.
class LibraryUpdater {
  LibraryUpdater(this._mangas, this._chapters, this._extensions,
      this._categories, this._downloads);

  final MangaRepository _mangas;
  final ChapterRepository _chapters;
  final ExtensionRepository _extensions;
  final CategoryRepository _categories;
  final DownloadRepository _downloads;

  late final FilterChaptersForDownload _downloadFilter =
      FilterChaptersForDownload(_chapters, _categories);

  /// Mihon's `SManga.COMPLETED`. A manga with this source status is skipped
  /// when the "Skip completed" restriction is active.
  static const int _statusCompleted = 2;

  /// Default-category sentinel (matches [FilterChaptersForDownload]): a manga
  /// with no user categories is treated as belonging to category id 0 for the
  /// global-update include/exclude match.
  static const int _defaultCategoryId = 0;

  /// Per-category convenience for the Library tab. Resolves the
  /// category's membership and forwards to [updateAll].
  Future<LibraryUpdateResult> updateCategory(
    int categoryId, {
    void Function(LibraryUpdateProgress)? onProgress,
  }) async {
    final mangaIds = await _categories.getMangaIdsInCategory(categoryId);
    return updateAll(
      onProgress: onProgress,
      restrictToMangaIds: mangaIds,
    );
  }

  /// Runs a library update pass. By default sweeps every favourited
  /// manga; pass [restrictToMangaIds] to limit the sweep to a specific
  /// subset (used by the "Update this category" affordance — the caller
  /// already knows which manga rows live in the active category, no need
  /// to re-query the join table here).
  Future<LibraryUpdateResult> updateAll({
    void Function(LibraryUpdateProgress)? onProgress,
    Set<int>? restrictToMangaIds,
  }) async {
    final favourites = await _mangas.getFavorites();
    final eligible = await _selectMangaToUpdate(favourites, restrictToMangaIds);

    // Read once per sweep: when on, each entry also has its details refreshed
    // (cover/description/status), not just its chapter list. Mirrors Kotlin's
    // `autoUpdateMetadata`. Read straight from prefs so this works in the
    // background workmanager isolate (no Riverpod).
    final prefs = await SharedPreferences.getInstance();
    final refreshMetadata = prefs.getBool('auto_update_metadata') ?? false;

    var newChaptersTotal = 0;
    var mangaWithNewChapters = 0;
    final failures = <LibraryUpdateFailure>[];
    for (var i = 0; i < eligible.length; i++) {
      final manga = eligible[i];
      onProgress?.call(LibraryUpdateProgress(
        completed: i,
        total: eligible.length,
        currentTitle: manga.title,
      ));
      try {
        final newCount = await _updateOne(manga, refreshMetadata);
        newChaptersTotal += newCount;
        if (newCount > 0) mangaWithNewChapters++;
      } catch (e) {
        failures.add(LibraryUpdateFailure(manga: manga, error: e.toString()));
      }
    }
    onProgress?.call(LibraryUpdateProgress(
      completed: eligible.length,
      total: eligible.length,
      currentTitle: null,
    ));
    return LibraryUpdateResult(
      mangaChecked: eligible.length,
      newChapters: newChaptersTotal,
      mangaWithNewChapters: mangaWithNewChapters,
      failures: failures,
    );
  }

  /// Applies the category include/exclude scope and the per-manga "smart
  /// update" restrictions to the favourite list, returning the manga that
  /// should actually be fetched this pass. 1:1 port of Mihon's
  /// `LibraryUpdateJob.addMangaToQueue` filter chain.
  ///
  /// Preferences are read straight from [SharedPreferences] so the same
  /// filtering runs in the background workmanager isolate (no Riverpod).
  /// [restrictToMangaIds] (the per-category "update this category" path)
  /// replaces the global include/exclude scope with explicit membership; the
  /// restrictions still apply on top.
  Future<List<Manga>> _selectMangaToUpdate(
    List<Manga> favourites,
    Set<int>? restrictToMangaIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final restrictions =
        (prefs.getStringList('library_update_manga_restriction') ??
                const [
                  MangaUpdateRestriction.hasUnread,
                  MangaUpdateRestriction.nonCompleted,
                  MangaUpdateRestriction.nonRead,
                  MangaUpdateRestriction.outsideReleasePeriod,
                ])
            .toSet();
    final included = _parseIds(prefs.getStringList('library_update_categories'));
    final excluded =
        _parseIds(prefs.getStringList('library_update_categories_exclude'));
    final fetchWindowUpper =
        const FetchInterval().getWindow(DateTime.now()).$2;

    final out = <Manga>[];
    for (final manga in favourites) {
      // Category scope: explicit membership for a per-category run, otherwise
      // the global include/exclude sets (exclusion wins over inclusion).
      if (restrictToMangaIds != null) {
        if (!restrictToMangaIds.contains(manga.id)) continue;
      } else if (included.isNotEmpty || excluded.isNotEmpty) {
        final cats = await _categories.getCategoryIdsForManga(manga.id);
        final effective = cats.isEmpty ? <int>{_defaultCategoryId} : cats;
        final isIncluded = included.isEmpty || effective.any(included.contains);
        final isExcluded = effective.any(excluded.contains);
        if (!isIncluded || isExcluded) continue;
      }

      // Restrictions that need chapter read-state counts.
      final chapters = await _chapters.getByMangaId(manga.id);
      final total = chapters.length;
      final hasUnread = chapters.any((c) => !c.read);
      final hasStarted = chapters.any((c) => c.read);

      // One-shot sources are fetched exactly once; skip after the first pull.
      if (manga.updateStrategy == UpdateStrategy.onlyFetchOnce && total > 0) {
        continue;
      }
      if (restrictions.contains(MangaUpdateRestriction.nonCompleted) &&
          manga.status == _statusCompleted) {
        continue;
      }
      if (restrictions.contains(MangaUpdateRestriction.hasUnread) && hasUnread) {
        continue;
      }
      if (restrictions.contains(MangaUpdateRestriction.nonRead) &&
          total > 0 &&
          !hasStarted) {
        continue;
      }
      if (restrictions.contains(MangaUpdateRestriction.outsideReleasePeriod) &&
          manga.nextUpdate > fetchWindowUpper) {
        continue;
      }
      out.add(manga);
    }
    return out;
  }

  Set<int> _parseIds(List<String>? raw) =>
      (raw ?? const []).map(int.tryParse).whereType<int>().toSet();

  /// Fetches a single manga's chapter list and persists any new chapters.
  /// When [refreshMetadata] is set, the manga's details (cover/description/
  /// status) are pulled and persisted first, matching Kotlin's
  /// `autoUpdateMetadata` path. Returns the number of chapters newly added.
  Future<int> _updateOne(Manga manga, bool refreshMetadata) async {
    final source = await _extensions.getSource(manga.source.toString());
    if (refreshMetadata) {
      final details = await source.fetchMangaDetails(
        SourceManga(url: manga.url, title: manga.title),
      );
      await _mangas.applySourceDetails(manga.id, details);
    }
    final fetched = await source.fetchChapterList(
      SourceManga(url: manga.url, title: manga.title),
    );
    final added = await _chapters.syncChaptersWithSource(manga.id, fetched);
    await recomputeFetchInterval(
      manga,
      hasNewChapters: added.isNotEmpty,
    );
    await downloadNewChapters(manga, added);
    return added.length;
  }

  /// Queues downloads for the subset of [newChapters] that pass the
  /// auto-download preferences (download_new + unread-only + category
  /// include/exclude), mirroring Mihon's post-sync `downloadChapters`
  /// step. No-op when auto-download is off or nothing qualifies. Shared by
  /// the library sweep and the per-manga details refresh.
  Future<void> downloadNewChapters(
    Manga manga,
    List<Chapter> newChapters,
  ) async {
    final toDownload = await _downloadFilter.filter(manga, newChapters);
    for (final chapter in toDownload) {
      await _downloads.enqueue(manga, chapter);
    }
  }

  /// Recomputes a manga's update interval + projected next-update from its
  /// current chapter history and persists it. Shared by the library sweep
  /// and the per-manga details refresh so both keep the Upcoming screen's
  /// `next_update` column fresh. Mirrors Mihon's post-sync
  /// `updateFetchInterval` step.
  Future<void> recomputeFetchInterval(
    Manga manga, {
    required bool hasNewChapters,
  }) async {
    final chapters = await _chapters.getByMangaId(manga.id);
    final update = const FetchInterval().toMangaUpdate(
      manga,
      chapters,
      DateTime.now(),
      hasNewChapters: hasNewChapters,
    );
    await _mangas.applyFetchInterval(
      manga.id,
      fetchInterval: update.fetchInterval,
      nextUpdate: update.nextUpdate,
      lastUpdate: update.lastUpdate,
    );
  }
}

class LibraryUpdateProgress {
  const LibraryUpdateProgress({
    required this.completed,
    required this.total,
    required this.currentTitle,
  });

  final int completed;
  final int total;
  final String? currentTitle;
}

class LibraryUpdateFailure {
  const LibraryUpdateFailure({required this.manga, required this.error});

  final Manga manga;
  final String error;
}

class LibraryUpdateResult {
  const LibraryUpdateResult({
    required this.mangaChecked,
    required this.newChapters,
    required this.mangaWithNewChapters,
    required this.failures,
  });

  final int mangaChecked;
  final int newChapters;

  /// How many distinct titles gained at least one new chapter. Drives the
  /// "N new chapters across M titles" notification copy.
  final int mangaWithNewChapters;
  final List<LibraryUpdateFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

final libraryUpdaterProvider = Provider<LibraryUpdater>((ref) {
  return LibraryUpdater(
    ref.watch(mangaRepositoryProvider),
    ref.watch(chapterRepositoryProvider),
    ref.watch(extensionRepositoryProvider),
    ref.watch(categoryRepositoryProvider),
    ref.watch(downloadRepositoryProvider),
  );
});
