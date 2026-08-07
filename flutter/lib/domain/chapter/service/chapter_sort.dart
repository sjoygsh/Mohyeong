import '../../manga/model/manga.dart';
import '../model/chapter.dart';

/// Orders a manga's chapters by its own `chapter_flags` sort setting.
///
/// Port of Kotlin `getChapterSort` (domain `ChapterSort.kt`), kept in the same
/// layer it lives in there — the details screen, the "next unread" pick and
/// the reader's sibling list all need the same answer, and it is pure enough
/// to test directly.
///
/// The source-order case inverts its direction relative to the others on
/// purpose: sources return chapters newest-first, so `sourceOrder == 0` is the
/// NEWEST chapter. That quirk is the fork's and is reproduced verbatim.
int compareChapters(Chapter a, Chapter b, Manga manga) {
  final primary = _primary(a, b, manga);
  if (primary != 0) return primary;
  // Kotlin gets a deterministic answer here for free: `sortedWith` is a STABLE
  // sort, so tied chapters keep the order they arrived in, which is
  // `getChaptersByMangaId`'s `ORDER BY source_order`. Dart's `List.sort` is
  // NOT stable, so without this the tied run comes back in an arbitrary order
  // that can differ between rebuilds of the same list.
  //
  // Ties are ordinary, not exotic: a source that publishes no upload dates
  // leaves `dateUpload` 0 on every row, so sorting by upload date is ONE giant
  // tie and the whole chapter list can reshuffle as you use the screen.
  // Falling back to `sourceOrder` reproduces exactly what a stable sort over
  // that input would have given, in both directions — ties keep INPUT order
  // regardless of which way the primary key runs.
  return a.sourceOrder.compareTo(b.sourceOrder);
}

/// [compareChapters] bound to one manga, for `list.sort(...)`.
int Function(Chapter, Chapter) chapterSortComparator(Manga manga) =>
    (a, b) => compareChapters(a, b, manga);

int _primary(Chapter a, Chapter b, Manga manga) {
  final desc = manga.sortDescending();
  switch (manga.sorting) {
    case Manga.chapterSortingNumber:
      return desc
          ? b.chapterNumber.compareTo(a.chapterNumber)
          : a.chapterNumber.compareTo(b.chapterNumber);
    case Manga.chapterSortingUploadDate:
      return desc
          ? b.dateUpload.compareTo(a.dateUpload)
          : a.dateUpload.compareTo(b.dateUpload);
    case Manga.chapterSortingAlphabet:
      return desc
          ? b.name.toLowerCase().compareTo(a.name.toLowerCase())
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    default: // chapterSortingSource
      return desc
          ? a.sourceOrder.compareTo(b.sourceOrder)
          : b.sourceOrder.compareTo(a.sourceOrder);
  }
}
