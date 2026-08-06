import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../manga/manga_repository.dart';
import '../track/track_repository.dart';

/// Per-axis toggles for a migration run. Mirrors the checkboxes on
/// Mihon's migration confirmation dialog.
class MigrationOptions {
  const MigrationOptions({
    this.copyChapters = true,
    this.copyCategories = true,
    this.copyTracks = true,
    this.deleteSourceManga = true,
  });

  /// Carry per-chapter read state, bookmarks and last-page-read from the
  /// source to the target by matching on chapter number.
  final bool copyChapters;

  /// Apply the source's category memberships to the target.
  final bool copyCategories;

  /// Re-create every tracker row pointed at the source so it points at
  /// the target instead. Source rows are dropped to avoid duplicates.
  final bool copyTracks;

  /// Unfavourite the source manga after migration. Most users want this
  /// — leaving it favourited means it stays in the library.
  final bool deleteSourceManga;
}

/// Source-to-source manga migration. The target manga must already
/// exist as a database row (typically inserted by the source-browse
/// flow). This service does not fetch chapters from the network — the
/// caller is responsible for ensuring [targetManga] has chapters
/// populated via the normal `LibraryUpdater` / source path.
class MigrationService {
  MigrationService({
    required this.mangaRepo,
    required this.chapterRepo,
    required this.categoryRepo,
    required this.trackRepo,
  });

  final MangaRepository mangaRepo;
  final ChapterRepository chapterRepo;
  final CategoryRepository categoryRepo;
  final TrackRepository trackRepo;

  Future<void> migrate({
    required Manga source,
    required Manga target,
    MigrationOptions options = const MigrationOptions(),
  }) async {
    // Step 1: favourite the target so it appears in the library before
    // any of the bulkier copy operations run.
    await mangaRepo.setFavorite(target.id, true);

    if (options.copyCategories) {
      final cats = await categoryRepo.getCategoryIdsForManga(source.id);
      await categoryRepo.setCategoriesForManga(target.id, cats);
    }

    if (options.copyChapters) {
      await _copyChapterProgress(source.id, target.id);
    }

    if (options.copyTracks) {
      await _copyTracks(source.id, target.id);
    }

    if (options.deleteSourceManga) {
      await mangaRepo.setFavorite(source.id, false);
      await categoryRepo.setCategoriesForManga(source.id, const <int>{});
    }
  }

  /// Match chapters by `chapterNumber` (rounded to two decimal places to
  /// absorb the float jitter sources frequently introduce). For each
  /// matching pair, propagate read state, bookmark, and the highest
  /// `lastPageRead`. Target chapters with no match are left untouched.
  Future<void> _copyChapterProgress(int sourceMangaId, int targetMangaId) async {
    final sourceChapters = await chapterRepo.getByMangaId(sourceMangaId);
    if (sourceChapters.isEmpty) return;
    final targetChapters = await chapterRepo.getByMangaId(targetMangaId);
    if (targetChapters.isEmpty) return;

    final byNumber = <String, Chapter>{};
    for (final c in sourceChapters) {
      final key = _numberKey(c.chapterNumber);
      // If multiple source chapters claim the same number, prefer the
      // one with more progress so we don't lose state.
      final existing = byNumber[key];
      if (existing == null || _progressScore(c) > _progressScore(existing)) {
        byNumber[key] = c;
      }
    }

    // Collected first, then written in one transaction: a chapter needing all
    // three fields used to cost three separate untransacted UPDATEs, and a
    // long series is thousands of them.
    final updates = <({
      int chapterId,
      bool? read,
      bool? bookmark,
      int? lastPageRead
    })>[];
    for (final t in targetChapters) {
      final key = _numberKey(t.chapterNumber);
      final s = byNumber[key];
      if (s == null) continue;
      final read = s.read && !t.read ? true : null;
      final bookmark = s.bookmark && !t.bookmark ? true : null;
      final lastPageRead =
          s.lastPageRead > t.lastPageRead ? s.lastPageRead : null;
      if (read == null && bookmark == null && lastPageRead == null) continue;
      updates.add((
        chapterId: t.id,
        read: read,
        bookmark: bookmark,
        lastPageRead: lastPageRead,
      ));
    }
    await chapterRepo.mergeProgress(updates);
  }

  Future<void> _copyTracks(int sourceMangaId, int targetMangaId) async {
    final sourceTracks = await trackRepo.getByMangaId(sourceMangaId);
    if (sourceTracks.isEmpty) return;
    final existingTargetTracks = await trackRepo.getByMangaId(targetMangaId);
    final targetTrackerIds = {
      for (final t in existingTargetTracks) t.trackerId,
    };
    for (final s in sourceTracks) {
      // Don't clobber a tracker row the target already has — leaving
      // both means the user can resolve manually.
      if (targetTrackerIds.contains(s.trackerId)) continue;
      await trackRepo.upsert(s.copyWith(id: 0, mangaId: targetMangaId));
      await trackRepo.delete(
        mangaId: sourceMangaId,
        trackerId: s.trackerId,
      );
    }
  }

  static String _numberKey(double n) => n.toStringAsFixed(2);

  static int _progressScore(Chapter c) {
    var score = 0;
    if (c.read) score += 1000;
    if (c.bookmark) score += 100;
    score += c.lastPageRead;
    return score;
  }
}

final migrationServiceProvider = Provider<MigrationService>((ref) {
  return MigrationService(
    mangaRepo: ref.watch(mangaRepositoryProvider),
    chapterRepo: ref.watch(chapterRepositoryProvider),
    categoryRepo: ref.watch(categoryRepositoryProvider),
    trackRepo: ref.watch(trackRepositoryProvider),
  );
});
