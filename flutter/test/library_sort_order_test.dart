import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/cover/cover_cache.dart';
import 'package:mohyeong/data/library/library_repository.dart';
import 'package:mohyeong/domain/category/model/category.dart';
import 'package:mohyeong/domain/library/model/library_item.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/manga/model/update_strategy.dart';
import 'package:mohyeong/presentation/library/library_screen.dart';

/// Two contracts the library grid's ordering has to keep, both taken from
/// Kotlin `LibraryScreenModel`:
///
///  * sorting by unread puts series with NOTHING LEFT TO READ last, in both
///    directions ("Ensure unread content comes first"). A plain numeric
///    compare headed the shelf with everything already finished whenever the
///    sort ran ascending.
///  * every sort falls back to title on a tie (`.thenComparator`). Ties are
///    the common case — every never-opened series shares `lastRead` 0 — and
///    Dart's `List.sort` is not stable, so without the tie-break the grid can
///    reorder itself between rebuilds with nothing having changed.
Manga _manga(int id, String title) => Manga(
      id: id,
      source: 1,
      favorite: true,
      lastUpdate: 0,
      nextUpdate: 0,
      fetchInterval: 0,
      dateAdded: 0,
      viewerFlags: 0,
      chapterFlags: 0,
      coverLastModified: 0,
      url: '/manga/$id',
      title: title,
      artist: null,
      author: 'Author $id',
      description: null,
      genre: const [],
      status: 1,
      thumbnailUrl: null,
      updateStrategy: UpdateStrategy.alwaysUpdate,
      initialized: true,
      lastModifiedAt: 0,
      favoriteModifiedAt: null,
      version: 1,
      notes: '',
    );

LibraryItem _item(int id, String title, {required int unread}) => LibraryItem(
      manga: _manga(id, title),
      unreadCount: unread,
      totalCount: 20,
      readCount: 20 - unread,
      bookmarkCount: 0,
      latestUpload: 0,
      chapterFetchedAt: 0,
      lastRead: 0,
      categoryIds: const <int>{},
    );

Stream<T> _replaying<T>(T value) => Stream<T>.multi((controller) {
      controller.add(value);
      controller.close();
    });

class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(this.items);
  final List<LibraryItem> items;

  @override
  Stream<List<LibraryItem>> watchAll() => _replaying(items);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Stream<List<Category>> watchAll() => _replaying(const <Category>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoverCache implements CoverCache {
  @override
  String? coverUrlFor(int mangaId, String? thumbnailUrl) => thumbnailUrl;

  @override
  bool hasCustomCover(int mangaId) => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<LibraryItem> items,
  required String axis,
  required String direction,
}) async {
  SharedPreferences.setMockInitialValues({
    'pref_library_sort_axis': axis,
    'pref_library_sort_direction': direction,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider
            .overrideWithValue(_FakeLibraryRepository(items)),
        categoryRepositoryProvider.overrideWithValue(_FakeCategoryRepository()),
        coverCacheProvider.overrideWithValue(_FakeCoverCache()),
      ],
      child: const MaterialApp(home: LibraryScreen()),
    ),
  );
  await _settle(tester);
}

/// Titles in the order the grid lays them out.
List<String> _titlesInOrder(WidgetTester tester, List<String> candidates) {
  final seen = <String>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final data = w.data;
    if (data != null && candidates.contains(data) && !seen.contains(data)) {
      seen.add(data);
    }
  }
  return seen;
}

void main() {
  const titles = ['Alpha', 'Bravo', 'Charlie', 'Delta'];

  testWidgets('sorting by unread ascending sinks the finished series',
      (WidgetTester tester) async {
    await _pump(
      tester,
      items: [
        _item(1, 'Alpha', unread: 0),
        _item(2, 'Bravo', unread: 5),
        _item(3, 'Charlie', unread: 2),
      ],
      axis: 'unread',
      direction: 'asc',
    );

    // Ascending by count would put Alpha (0 unread) first. The fork's rule
    // keeps what you still have to read at the top and sinks Alpha.
    expect(
      _titlesInOrder(tester, titles),
      ['Charlie', 'Bravo', 'Alpha'],
    );
  });

  testWidgets('sorting by unread descending also sinks the finished series',
      (WidgetTester tester) async {
    await _pump(
      tester,
      items: [
        _item(1, 'Alpha', unread: 0),
        _item(2, 'Bravo', unread: 5),
        _item(3, 'Charlie', unread: 2),
      ],
      axis: 'unread',
      direction: 'desc',
    );

    expect(
      _titlesInOrder(tester, titles),
      ['Bravo', 'Charlie', 'Alpha'],
    );
  });

  testWidgets('a tie on the sort axis falls back to title', (tester) async {
    // Every item shares lastRead 0 — the ordinary case for a shelf nobody has
    // opened yet — so the whole order is decided by the tie-break.
    await _pump(
      tester,
      items: [
        _item(1, 'Delta', unread: 1),
        _item(2, 'Bravo', unread: 1),
        _item(3, 'Alpha', unread: 1),
      ],
      axis: 'last_read',
      direction: 'asc',
    );

    expect(_titlesInOrder(tester, titles), ['Alpha', 'Bravo', 'Delta']);
  });

  testWidgets('the tie-break stays alphabetical when the sort is descending',
      (tester) async {
    await _pump(
      tester,
      items: [
        _item(1, 'Delta', unread: 1),
        _item(2, 'Bravo', unread: 1),
        _item(3, 'Alpha', unread: 1),
      ],
      axis: 'last_read',
      direction: 'desc',
    );

    // Reversing applies to the axis, not to the alphabet — same as the fork,
    // where `.reversed()` wraps only the axis comparator before
    // `.thenComparator(sortAlphabetically)` is appended.
    expect(_titlesInOrder(tester, titles), ['Alpha', 'Bravo', 'Delta']);
  });
}
