import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/cover/cover_cache.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/library/library_repository.dart';
import 'package:mohyeong/data/library/library_updater.dart';
import 'package:mohyeong/data/updates/updates_repository.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/set_read_status.dart';
import 'package:mohyeong/domain/library/model/library_item.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/manga/model/update_strategy.dart';
import 'package:mohyeong/presentation/tide/tide.dart';
import 'package:mohyeong/presentation/tide/tide_home_screen.dart';

/// Tide's home draws four data-fed things — a rotating hero, a horizontal
/// rail, and the Tonight feed, which IS the updates surface now that there is
/// no separate Updates page. None of it is reached by the shell test, which
/// runs against empty repositories. This renders the populated screen so a
/// layout fault in any of them fails here rather than on a phone, and pins the
/// updates behaviour that moved onto this screen.

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
      description: 'Description for $title.',
      genre: const ['Fantasy', 'Action', 'Romance'],
      status: 1,
      // No artwork: TideCover falls back to its deterministic gradient, which
      // is the path a test can actually exercise (no network).
      thumbnailUrl: null,
      updateStrategy: UpdateStrategy.alwaysUpdate,
      initialized: true,
      lastModifiedAt: 0,
      favoriteModifiedAt: null,
      version: 1,
      notes: '',
    );

LibraryItem _item(int id, String title,
        {required int read, required int total}) =>
    LibraryItem(
      manga: _manga(id, title),
      unreadCount: total - read,
      totalCount: total,
      readCount: read,
      bookmarkCount: 0,
      latestUpload: 0,
      chapterFetchedAt: 0,
      lastRead: 0,
      categoryIds: const <int>{},
    );

LibraryUpdate _update({
  required int mangaId,
  required String mangaTitle,
  required int chapterId,
  required String chapterName,
  required int dateFetch,
  bool read = false,
  bool bookmark = false,
}) =>
    LibraryUpdate(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterId: chapterId,
      chapterName: chapterName,
      scanlator: null,
      chapterUrl: '/c/$chapterId',
      read: read,
      bookmark: bookmark,
      lastPageRead: 0,
      source: 1,
      thumbnailUrl: null,
      coverLastModified: 0,
      dateUpload: dateFetch,
      dateFetch: dateFetch,
      excludedScanlator: null,
      isLinkedAttribution: false,
    );

class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(this.items);

  final List<LibraryItem> items;

  @override
  Stream<List<LibraryItem>> watchAll() => Stream.value(items);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository(this.entries);

  final List<HistoryWithContext> entries;

  @override
  Stream<List<HistoryWithContext>> watchRecent({int limit = 200}) =>
      Stream.value(entries);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Covers resolve through the real cache in the app; here every entry has no
/// artwork, so the fake just reports the (absent) source URL and the cover
/// falls back to its gradient.
class _FakeCoverCache implements CoverCache {
  @override
  String? coverUrlFor(int mangaId, String? thumbnailUrl) => thumbnailUrl;

  @override
  bool hasCustomCover(int mangaId) => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUpdatesRepository implements UpdatesRepository {
  _FakeUpdatesRepository(this.updates);

  final List<LibraryUpdate> updates;

  @override
  Stream<List<LibraryUpdate>> watchAll({
    Duration window = const Duration(days: 90),
    int limit = 500,
  }) =>
      Stream.value(updates);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records that the header control actually ran a library update.
class _FakeLibraryUpdater implements LibraryUpdater {
  int calls = 0;

  @override
  Future<LibraryUpdateResult> updateAll({
    void Function(LibraryUpdateProgress)? onProgress,
    Set<int>? restrictToMangaIds,
  }) async {
    calls++;
    return const LibraryUpdateResult(
      mangaChecked: 3,
      newChapters: 2,
      mangaWithNewChapters: 1,
      failures: [],
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChapterRepository implements ChapterRepository {
  @override
  Future<List<Chapter>> getByMangaId(int mangaId) async => const <Chapter>[];

  /// The bulk mark-read resolves the selected ids straight to rows rather
  /// than reading each owning series whole, so this hands back one row per
  /// id — enough for the interactor to be called with something real.
  @override
  Future<List<Chapter>> getByIds(Iterable<int> ids) async => [
        for (final id in ids)
          Chapter(
            id: id,
            mangaId: 1,
            read: false,
            bookmark: false,
            lastPageRead: 0,
            dateFetch: 0,
            sourceOrder: 0,
            url: 'ch/$id',
            name: 'Chapter $id',
            dateUpload: 0,
            chapterNumber: 1,
            scanlator: null,
            lastModifiedAt: 0,
            version: 0,
          ),
      ];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the bulk mark-read call so the selection bar's wiring is asserted
/// rather than just its pixels.
class _FakeSetReadStatus implements SetReadStatus {
  final List<bool> calls = [];

  @override
  Future<void> setRead({
    required bool read,
    required List<Chapter> chapters,
  }) async {
    calls.add(read);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {int frames = 6}) async {
  // Explicit pumps, not pumpAndSettle: the aurora and the hero's slow zoom
  // never stop, so the frame queue never drains.
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Anchored to midnight so the day buckets don't depend on the clock.
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final todayMs = midnight.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
  final threeDaysAgoMs =
      midnight.subtract(const Duration(days: 3)).millisecondsSinceEpoch;

  final items = <LibraryItem>[
    _item(1, 'Ending Maker', read: 42, total: 67),
    _item(2, 'Nano Machine', read: 44, total: 220),
    _item(3, 'Omniscient Reader', read: 158, total: 180),
  ];
  final history = <HistoryWithContext>[
    HistoryWithContext(
      historyId: 1,
      chapterId: 10,
      mangaId: 1,
      mangaTitle: 'Ending Maker',
      chapterName: 'Chapter 42',
      chapterNumber: 42,
      readAt: DateTime(2026, 7, 25, 20),
      timeReadMs: 1000,
      source: 1,
      thumbnailUrl: null,
    ),
    HistoryWithContext(
      historyId: 2,
      chapterId: 20,
      mangaId: 3,
      mangaTitle: 'Omniscient Reader',
      chapterName: 'Chapter 158',
      chapterNumber: 158,
      readAt: DateTime(2026, 7, 25, 18),
      timeReadMs: 1000,
      source: 1,
      thumbnailUrl: null,
    ),
  ];
  final updates = <LibraryUpdate>[
    _update(
      mangaId: 1,
      mangaTitle: 'Ending Maker',
      chapterId: 99,
      chapterName: 'Chapter 67',
      dateFetch: todayMs,
    ),
    _update(
      mangaId: 3,
      mangaTitle: 'Omniscient Reader',
      chapterId: 98,
      chapterName: 'Chapter 159',
      dateFetch: threeDaysAgoMs,
    ),
  ];

  Future<(_FakeLibraryUpdater, _FakeSetReadStatus)> pumpHome(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final updater = _FakeLibraryUpdater();
    final setRead = _FakeSetReadStatus();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider
              .overrideWithValue(_FakeLibraryRepository(items)),
          historyRepositoryProvider
              .overrideWithValue(_FakeHistoryRepository(history)),
          updatesRepositoryProvider
              .overrideWithValue(_FakeUpdatesRepository(updates)),
          coverCacheProvider.overrideWithValue(_FakeCoverCache()),
          libraryUpdaterProvider.overrideWithValue(updater),
          chapterRepositoryProvider
              .overrideWithValue(_FakeChapterRepository()),
          setReadStatusProvider.overrideWithValue(setRead),
        ],
        child: const MaterialApp(home: TideHomeScreen()),
      ),
    );
    await _pump(tester);
    return (updater, setRead);
  }

  /// Tonight sits below the fold; the feed builds lazily, so scroll to it.
  Future<void> scrollToTonight(WidgetTester tester) async {
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -700),
    );
    await _pump(tester);
  }

  testWidgets('hero and continue rail render from the library streams',
      (WidgetTester tester) async {
    await pumpHome(tester);

    // Hero — the most-completed series (Omniscient Reader, 158/180) leads.
    expect(find.text('Omniscient Reader'), findsWidgets);
    expect(find.textContaining('MOST READ'), findsOneWidget);

    // Continue rail: both history entries resolve against the library, and
    // the caption carries the chapter plus how far through the series it is.
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Chapter 42 · 63%'), findsOneWidget);
    expect(find.text('Nothing part-read right now.'), findsNothing);
  });

  testWidgets('Tonight is the updates feed, and only older days get a header',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await scrollToTonight(tester);

    expect(find.text('TONIGHT'), findsOneWidget);
    expect(find.text('NEW'), findsWidgets);

    // Today's arrivals hang directly under TONIGHT — a "TODAY" header there
    // would say the same thing twice.
    expect(find.text('TODAY'), findsNothing);
    // An older arrival still gets its own day separator.
    final threeDaysAgo = midnight.subtract(const Duration(days: 3));
    const names = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    expect(find.text(names[(threeDaysAgo.weekday - 1) % 7]), findsOneWidget);
  });

  testWidgets('the header refresh control runs a library update',
      (WidgetTester tester) async {
    final (updater, _) = await pumpHome(tester);

    expect(updater.calls, 0);
    await tester.tap(find.byIcon(Icons.refresh));
    await _pump(tester);
    expect(updater.calls, 1);
  });

  testWidgets('long-press selects updates and the bar marks them read',
      (WidgetTester tester) async {
    final (_, setRead) = await pumpHome(tester);
    await scrollToTonight(tester);

    await tester.longPress(find.text('Ending Maker').last);
    await _pump(tester);

    // The header becomes the selection header and the bulk bar takes the tab
    // bar's place. skipOffstage: the header is at the top of the feed, which
    // is scrolled well out of the viewport by now, and a sliver outside the
    // viewport counts as offstage to a finder.
    expect(find.text('1 selected', skipOffstage: false), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Bookmark'), findsOneWidget);

    await tester.tap(find.text('Read'));
    await _pump(tester);
    expect(setRead.calls, [true]);
    // The selection clears once the action has run.
    expect(find.text('1 selected', skipOffstage: false), findsNothing);
  });

  testWidgets('the filter sheet exposes all three updates axes',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await scrollToTonight(tester);

    await tester.tap(find.byIcon(Icons.filter_list));
    await _pump(tester);

    expect(find.text('Filter updates'), findsOneWidget);
    expect(find.text('Unread'), findsOneWidget);
    expect(find.text('Bookmarked'), findsOneWidget);
    expect(find.text('Hide muted scanlators'), findsOneWidget);
    // Tri-states say what they are in words rather than hiding three states
    // behind one icon.
    expect(find.text('Off'), findsNWidgets(2));
  });

  test('tideRelative renders the design\'s compact stamps', () {
    final now = DateTime(2026, 7, 26, 12);
    expect(
        tideRelative(now.subtract(const Duration(minutes: 30)), now), '30m ago');
    expect(tideRelative(now.subtract(const Duration(hours: 4)), now), '4h ago');
    expect(
        tideRelative(now.subtract(const Duration(days: 1)), now), 'Yesterday');
    expect(
        tideRelative(now.subtract(const Duration(days: 8)), now), '1 week ago');
  });

  test('tideChapterLabel prefers the source name and falls back to a number',
      () {
    expect(tideChapterLabel('Ch. 42 — The Duel', 42), 'Ch. 42 — The Duel');
    expect(tideChapterLabel('', 42), 'Chapter 42');
    expect(tideChapterLabel('   ', 42.5), 'Chapter 42.5');
    expect(tideChapterLabel('', -1), 'Chapter');
  });
}
