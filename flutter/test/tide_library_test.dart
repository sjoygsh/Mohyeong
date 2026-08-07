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

/// The library's head is a masthead rather than a toolbar: the shelf's name at
/// display size over a kicker stating what is on it, folding into the control
/// row as the grid scrolls. That fold is motion no static screenshot proves,
/// and the device library is too small to scroll — so it is pinned here.

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
      // No artwork: TideCover falls back to its gradient, which is the path a
      // test can exercise without a network.
      thumbnailUrl: null,
      updateStrategy: UpdateStrategy.alwaysUpdate,
      initialized: true,
      lastModifiedAt: 0,
      favoriteModifiedAt: null,
      version: 1,
      notes: '',
    );

LibraryItem _item(int id, {required int unread}) => LibraryItem(
      manga: _manga(id, 'Series $id'),
      unreadCount: unread,
      totalCount: 20,
      readCount: 20 - unread,
      bookmarkCount: 0,
      latestUpload: 0,
      chapterFetchedAt: 0,
      lastRead: 0,
      categoryIds: const <int>{},
    );

/// `Stream.multi` rather than `Stream.value`: the real repository hands back a
/// Drift query stream, which is multi-subscription and replays current rows to
/// each new listener. The screen has more than one reader of it — the grid and
/// the heading — so a single-subscription fake would fail on a contract the
/// production stream actually meets.
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

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<LibraryItem> items,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider
            .overrideWithValue(_FakeLibraryRepository(items)),
        categoryRepositoryProvider
            .overrideWithValue(_FakeCategoryRepository()),
        coverCacheProvider.overrideWithValue(_FakeCoverCache()),
      ],
      child: const MaterialApp(home: LibraryScreen()),
    ),
  );
  await _settle(tester);
}

/// The aurora animates forever, so `pumpAndSettle` never returns on any Tide
/// screen. Pumping a fixed handful of frames is what "settled" means here.
Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// How much of the masthead is showing: 1 fully out, 0 folded away.
///
/// Read off the [Align] that does the folding rather than off the title's own
/// size — the title lays out at full height either way; what changes is how
/// much of it the header gives room to.
///
/// Fully folded, the masthead is not built at all: a zero-height [Align] still
/// lays its child out in full before clipping it away, and this subtree
/// rebuilds on every scrolled frame, so the header being gone is expressed by
/// its absence. No folding [Align] therefore reads as 0, not as a missing
/// widget — the tests below still pin the showing case, so a masthead that
/// vanished for the WRONG reason cannot pass.
double _mastheadShowing(WidgetTester tester) {
  final folds = tester
      .widgetList<Align>(find.byType(Align))
      .where((a) => a.heightFactor != null)
      .toList();
  if (folds.isEmpty) return 0;
  expect(folds, hasLength(1), reason: 'at most one folding Align expected');
  return folds.single.heightFactor!;
}

void main() {
  testWidgets('the masthead names the shelf and counts what is unread',
      (WidgetTester tester) async {
    await _pumpLibrary(tester, items: [
      _item(1, unread: 3),
      _item(2, unread: 4),
      _item(3, unread: 0),
    ]);

    expect(find.text('Library'), findsWidgets);
    // The unread total is the sum across the shelf, not a count of entries.
    expect(find.text('7 UNREAD'), findsOneWidget);
  });

  testWidgets('an empty shelf says so rather than showing a bare zero',
      (WidgetTester tester) async {
    await _pumpLibrary(tester, items: const []);

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('NOTHING HERE YET'), findsOneWidget);
  });

  testWidgets('a shelf with nothing waiting says it is caught up',
      (WidgetTester tester) async {
    await _pumpLibrary(tester, items: [_item(1, unread: 0)]);

    expect(find.text('ALL CAUGHT UP'), findsOneWidget);
  });

  testWidgets('scrolling the grid folds the masthead away, and back',
      (WidgetTester tester) async {
    await _pumpLibrary(tester, items: [
      for (var i = 1; i <= 40; i++) _item(i, unread: 1),
    ]);

    expect(_mastheadShowing(tester), 1.0);

    await tester.drag(find.byType(GridView), const Offset(0, -400));
    await _settle(tester);
    // Past the fold distance, so it is all the way away.
    expect(_mastheadShowing(tester), 0.0);

    // …and scrolling back to the top brings it out again, so the shelf's name
    // is never lost somewhere up-scroll.
    await tester.drag(find.byType(GridView), const Offset(0, 600));
    await _settle(tester);
    expect(_mastheadShowing(tester), 1.0);
  });

  testWidgets('a grid that shrinks under a folded masthead unfolds it',
      (WidgetTester tester) async {
    // The failure this guards: scroll down, then narrow the list until it no
    // longer scrolls. Without a metrics listener the masthead stays folded
    // with no gesture left that could bring it back.
    await _pumpLibrary(tester, items: [
      for (var i = 1; i <= 40; i++) _item(i, unread: 1),
    ]);
    await tester.drag(find.byType(GridView), const Offset(0, -400));
    await _settle(tester);
    expect(_mastheadShowing(tester), 0.0);

    await tester.tap(find.byIcon(Icons.search));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Series 7');
    await _settle(tester);

    expect(_mastheadShowing(tester), 1.0);
  });
}
