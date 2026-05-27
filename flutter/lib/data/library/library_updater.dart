import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/update_strategy.dart';
import '../../domain/source/model/source_manga.dart';
import '../chapter/chapter_repository.dart';
import '../manga/manga_repository.dart';
import '../source/extension_repository.dart';

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
  LibraryUpdater(this._mangas, this._chapters, this._extensions);

  final MangaRepository _mangas;
  final ChapterRepository _chapters;
  final ExtensionRepository _extensions;

  /// Runs a library update pass over every favourited manga. Emits per-manga
  /// progress on [progress]; returns a summary when complete.
  Future<LibraryUpdateResult> updateAll({
    void Function(LibraryUpdateProgress)? onProgress,
  }) async {
    final favourites = await _mangas.getFavorites();
    final eligible = favourites
        .where((m) => m.updateStrategy == UpdateStrategy.alwaysUpdate)
        .toList(growable: false);

    var newChaptersTotal = 0;
    final failures = <LibraryUpdateFailure>[];
    for (var i = 0; i < eligible.length; i++) {
      final manga = eligible[i];
      onProgress?.call(LibraryUpdateProgress(
        completed: i,
        total: eligible.length,
        currentTitle: manga.title,
      ));
      try {
        final newCount = await _updateOne(manga);
        newChaptersTotal += newCount;
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
      failures: failures,
    );
  }

  /// Fetches a single manga's chapter list and persists any new chapters.
  /// Returns the number of chapters newly added to the DB.
  Future<int> _updateOne(Manga manga) async {
    final source = await _extensions.getSource(manga.source.toString());
    final fetched = await source.fetchChapterList(
      SourceManga(url: manga.url, title: manga.title),
    );
    final added = await _chapters.syncChaptersWithSource(manga.id, fetched);
    return added.length;
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
    required this.failures,
  });

  final int mangaChecked;
  final int newChapters;
  final List<LibraryUpdateFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

final libraryUpdaterProvider = Provider<LibraryUpdater>((ref) {
  return LibraryUpdater(
    ref.watch(mangaRepositoryProvider),
    ref.watch(chapterRepositoryProvider),
    ref.watch(extensionRepositoryProvider),
  );
});
