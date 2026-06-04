import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/category/category_repository.dart';
import '../../../data/chapter/chapter_repository.dart';
import '../../manga/model/manga.dart';
import '../model/chapter.dart';

/// Decides which of a manga's freshly-discovered chapters should be queued
/// for download after a library update. 1:1 port of Mihon's
/// `mihon.domain.chapter.interactor.FilterChaptersForDownload`.
///
/// Preferences are read straight from [SharedPreferences] (not Riverpod) so
/// the same logic runs in the background workmanager isolate, which has no
/// provider container.
class FilterChaptersForDownload {
  const FilterChaptersForDownload(this._chapters, this._categories);

  final ChapterRepository _chapters;
  final CategoryRepository _categories;

  /// Mihon's default-category sentinel: a manga with no user categories is
  /// treated as belonging to category id 0 for include/exclude matching.
  static const int _defaultCategoryId = 0;

  Future<List<Chapter>> filter(Manga manga, List<Chapter> newChapters) async {
    if (newChapters.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('download_new') ?? false)) return const [];
    if (!await _shouldDownloadNewChapters(manga, prefs)) return const [];

    if (!(prefs.getBool('download_new_unread_chapters_only') ?? false)) {
      return newChapters;
    }

    final readChapterNumbers = (await _chapters.getByMangaId(manga.id))
        .where((c) => c.read && c.isRecognizedNumber)
        .map((c) => c.chapterNumber)
        .toSet();
    return newChapters
        .where((c) => !readChapterNumbers.contains(c.chapterNumber))
        .toList(growable: false);
  }

  Future<bool> _shouldDownloadNewChapters(
    Manga manga,
    SharedPreferences prefs,
  ) async {
    if (!manga.favorite) return false;

    final categories = await _categories.getCategoryIdsForManga(manga.id);
    final effective =
        categories.isEmpty ? <int>{_defaultCategoryId} : categories;
    final included = _parseIds(prefs.getStringList('download_new_categories'));
    final excluded =
        _parseIds(prefs.getStringList('download_new_categories_exclude'));

    if (included.isEmpty && excluded.isEmpty) return true;
    if (effective.any(excluded.contains)) return false;
    if (included.isEmpty) return true;
    return effective.any(included.contains);
  }

  Set<int> _parseIds(List<String>? raw) =>
      (raw ?? const []).map(int.tryParse).whereType<int>().toSet();
}
