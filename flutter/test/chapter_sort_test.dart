import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/chapter_sort.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/manga/model/update_strategy.dart';

/// The chapter comparator, against Kotlin `getChapterSort` — including the
/// part Kotlin never had to write down.
///
/// `sortedWith` is a STABLE sort, so over there tied chapters keep the order
/// they arrived in (`ORDER BY source_order`). Dart's `List.sort` is not
/// stable, so the port needs an explicit tie-break to get the same answer. It
/// is not a corner case: a source that publishes no upload dates leaves
/// `dateUpload` 0 on every row, which makes "sort by upload date" one enormous
/// tie.
Manga _manga({required int sorting, required bool descending}) => Manga(
      id: 1,
      source: 1,
      favorite: true,
      lastUpdate: 0,
      nextUpdate: 0,
      fetchInterval: 0,
      dateAdded: 0,
      viewerFlags: 0,
      chapterFlags:
          sorting | (descending ? Manga.chapterSortDesc : Manga.chapterSortAsc),
      coverLastModified: 0,
      url: '/m/1',
      title: 'M',
      artist: null,
      author: null,
      description: null,
      genre: const [],
      status: 1,
      thumbnailUrl: null,
      updateStrategy: UpdateStrategy.alwaysUpdate,
      initialized: true,
      lastModifiedAt: 0,
      favoriteModifiedAt: null,
      version: 0,
      notes: '',
    );

Chapter _chapter(
  int id, {
  required int sourceOrder,
  double number = 1,
  int dateUpload = 0,
  String name = 'Chapter',
}) =>
    Chapter(
      id: id,
      mangaId: 1,
      read: false,
      bookmark: false,
      lastPageRead: 0,
      dateFetch: 0,
      sourceOrder: sourceOrder,
      url: '/c/$id',
      name: name,
      dateUpload: dateUpload,
      chapterNumber: number,
      scanlator: null,
      lastModifiedAt: 0,
      version: 0,
      bookmarkNote: null,
      volumeNumber: null,
    );

List<int> _sortedIds(List<Chapter> chapters, Manga manga) =>
    ([...chapters]..sort(chapterSortComparator(manga)))
        .map((c) => c.id)
        .toList();

void main() {
  group('primary keys match getChapterSort', () {
    test('by number, both directions', () {
      final chapters = [
        _chapter(1, sourceOrder: 0, number: 3),
        _chapter(2, sourceOrder: 1, number: 1),
        _chapter(3, sourceOrder: 2, number: 2),
      ];
      expect(
        _sortedIds(
            chapters,
            _manga(
                sorting: Manga.chapterSortingNumber, descending: false)),
        [2, 3, 1],
      );
      expect(
        _sortedIds(chapters,
            _manga(sorting: Manga.chapterSortingNumber, descending: true)),
        [1, 3, 2],
      );
    });

    test('source order inverts relative to the other axes', () {
      // sourceOrder 0 is the NEWEST chapter, so "descending" runs 0,1,2.
      final chapters = [
        _chapter(1, sourceOrder: 2),
        _chapter(2, sourceOrder: 0),
        _chapter(3, sourceOrder: 1),
      ];
      expect(
        _sortedIds(chapters,
            _manga(sorting: Manga.chapterSortingSource, descending: true)),
        [2, 3, 1],
      );
      expect(
        _sortedIds(chapters,
            _manga(sorting: Manga.chapterSortingSource, descending: false)),
        [1, 3, 2],
      );
    });
  });

  group('ties resolve the way a stable sort would', () {
    test('a source with no upload dates keeps source order, ascending', () {
      // Every dateUpload is 0 — the entire list is one tie.
      final chapters = [
        _chapter(1, sourceOrder: 2),
        _chapter(2, sourceOrder: 0),
        _chapter(3, sourceOrder: 1),
      ];
      expect(
        _sortedIds(chapters,
            _manga(sorting: Manga.chapterSortingUploadDate, descending: false)),
        [2, 3, 1],
      );
    });

    test('and keeps the SAME order when the sort runs descending', () {
      // Ties keep input order regardless of direction — reversal applies to
      // the primary key, not to the tie-break.
      final chapters = [
        _chapter(1, sourceOrder: 2),
        _chapter(2, sourceOrder: 0),
        _chapter(3, sourceOrder: 1),
      ];
      expect(
        _sortedIds(chapters,
            _manga(sorting: Manga.chapterSortingUploadDate, descending: true)),
        [2, 3, 1],
      );
    });

    test('two scanlators publishing the same number order deterministically',
        () {
      final chapters = [
        _chapter(1, sourceOrder: 5, number: 7),
        _chapter(2, sourceOrder: 3, number: 7),
        _chapter(3, sourceOrder: 4, number: 7),
      ];
      final manga =
          _manga(sorting: Manga.chapterSortingNumber, descending: false);
      expect(_sortedIds(chapters, manga), [2, 3, 1]);
      // Re-sorting an already-sorted list must not move anything.
      expect(_sortedIds([...chapters]..sort(chapterSortComparator(manga)),
          manga), [2, 3, 1]);
    });

    test('the order does not depend on the order it was handed in', () {
      final manga =
          _manga(sorting: Manga.chapterSortingUploadDate, descending: false);
      final a = [
        _chapter(1, sourceOrder: 0),
        _chapter(2, sourceOrder: 1),
        _chapter(3, sourceOrder: 2),
        _chapter(4, sourceOrder: 3),
        _chapter(5, sourceOrder: 4),
        _chapter(6, sourceOrder: 5),
        _chapter(7, sourceOrder: 6),
        _chapter(8, sourceOrder: 7),
        _chapter(9, sourceOrder: 8),
        _chapter(10, sourceOrder: 9),
        _chapter(11, sourceOrder: 10),
        _chapter(12, sourceOrder: 11),
      ];
      final shuffled = [...a.reversed];
      expect(_sortedIds(shuffled, manga), _sortedIds(a, manga));
      expect(_sortedIds(a, manga), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    });
  });
}
