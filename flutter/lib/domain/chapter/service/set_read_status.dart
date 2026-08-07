/// Port of Mihon's `SetReadStatus` interactor plus the reader's
/// `deleteChapterIfNeeded` slot logic — the two places downloaded chapters
/// are auto-removed once read.
///
///  * [setRead] flips the read flag for a batch of chapters and, when
///    `pref_remove_after_marked_as_read_key` is on, deletes their downloads
///    (skipping bookmarked chapters unless `pref_remove_bookmarked` is on,
///    and skipping manga in `remove_exclude_categories`). 1:1 with
///    `SetReadStatus.await`.
///  * [deleteReadChapterSlot] deletes the download `removeAfterReadSlots`
///    chapters behind the one just finished, in reading order. 1:1 with
///    `ReaderViewModel.deleteChapterIfNeeded`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/category/category_repository.dart';
import '../../../data/chapter/chapter_repository.dart';
import '../../../data/download/download_preferences.dart';
import '../../../data/download/download_repository.dart';
import '../../../data/manga/manga_repository.dart';
import '../../manga/model/manga.dart';
import '../model/chapter.dart';

class SetReadStatus {
  SetReadStatus(this._ref);

  final Ref _ref;

  /// Marks [chapters] read/unread (skipping no-op rows, matching Mihon's
  /// filter) and, when marking read with removal enabled, deletes their
  /// downloads.
  Future<void> setRead({
    required bool read,
    required List<Chapter> chapters,
  }) async {
    final toUpdate = chapters.where((c) {
      return read ? !c.read : (c.read || c.lastPageRead > 0);
    }).toList(growable: false);
    if (toUpdate.isEmpty) return;

    // One transaction, not one commit (and one stream invalidation) per
    // chapter — see [ChapterRepository.setReadForIds]. This is the path
    // behind every bulk mark-read in the app.
    final chapterRepo = _ref.read(chapterRepositoryProvider);
    await chapterRepo.setReadForIds(
      [for (final c in toUpdate) c.id],
      read,
    );

    if (!read || !_ref.read(removeAfterMarkedAsReadProvider)) return;

    final mangaRepo = _ref.read(mangaRepositoryProvider);
    final byManga = <int, List<Chapter>>{};
    for (final c in toUpdate) {
      (byManga[c.mangaId] ??= <Chapter>[]).add(c);
    }
    for (final entry in byManga.entries) {
      final manga = await mangaRepo.getById(entry.key);
      if (manga == null) continue;
      for (final c in entry.value) {
        await _deleteIfAllowed(manga, c);
      }
    }
  }

  /// Reader hook: after [current] is finished, delete the download
  /// `removeAfterReadSlots` positions earlier in [orderedChapters] (reading
  /// order). -1 disables; 0 removes [current] itself. No-op when the target
  /// slot doesn't exist.
  Future<void> deleteReadChapterSlot({
    required Manga manga,
    required List<Chapter> orderedChapters,
    required Chapter current,
  }) async {
    final slots = _ref.read(removeAfterReadSlotsProvider);
    if (slots == -1) return;

    final position = orderedChapters.indexWhere((c) => c.id == current.id);
    if (position < 0) return;
    final targetIndex = position - slots;
    if (targetIndex < 0 || targetIndex >= orderedChapters.length) return;

    await _deleteIfAllowed(manga, orderedChapters[targetIndex]);
  }

  /// Deletes [chapter]'s download unless it's protected — mirroring
  /// `DownloadManager.getChaptersToDelete`: bookmarked chapters are kept
  /// unless [removeBookmarkedChaptersProvider] is on, and manga in an
  /// excluded category ([removeExcludeCategoriesProvider]) keep their read
  /// chapters. Every chapter reaching this path is being removed because it
  /// just became read, so an excluded manga is skipped outright.
  Future<void> _deleteIfAllowed(Manga manga, Chapter chapter) async {
    if (chapter.bookmark && !_ref.read(removeBookmarkedChaptersProvider)) {
      return;
    }
    final excluded = _ref
        .read(removeExcludeCategoriesProvider)
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (excluded.isNotEmpty) {
      final cats =
          await _ref.read(categoryRepositoryProvider).getCategoryIdsForManga(
                manga.id,
              );
      // Mihon treats an uncategorized manga as category 0 for this check.
      final effective = cats.isEmpty ? const {0} : cats;
      if (effective.intersection(excluded).isNotEmpty) return;
    }
    await _ref
        .read(downloadRepositoryProvider)
        .deleteDownload(manga.source, manga.id, chapter.id);
  }
}

final setReadStatusProvider =
    Provider<SetReadStatus>((ref) => SetReadStatus(ref));
