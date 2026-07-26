import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/cover/cover_cache.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/library/library_repository.dart';
import 'package:mohyeong/data/updates/updates_repository.dart';
import 'package:mohyeong/domain/library/model/library_item.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/manga/model/update_strategy.dart';
import 'package:mohyeong/presentation/tide/tide.dart';
import 'package:mohyeong/presentation/tide/tide_home_screen.dart';

/// Tide's home draws three data-fed sections — a rotating hero, a horizontal
/// rail and a list — none of which the shell test reaches, because it runs
/// against empty repositories. This renders the populated screen so a layout
/// fault in any of them fails here rather than on a phone.

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

LibraryItem _item(int id, String title, {required int read, required int total}) =>
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
/// artwork, so the fake just reports the (absent) source URL and TideCover
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
  Stream<List<LibraryUpdate>> watchAll() => Stream.value(updates);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Tide home renders hero, continue rail and tonight list',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

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
      const LibraryUpdate(
        mangaId: 1,
        mangaTitle: 'Ending Maker',
        chapterId: 99,
        chapterName: 'Chapter 67',
        scanlator: null,
        chapterUrl: '/c/67',
        read: false,
        bookmark: false,
        lastPageRead: 0,
        source: 1,
        thumbnailUrl: null,
        coverLastModified: 0,
        dateUpload: 0,
        dateFetch: 0,
        excludedScanlator: null,
        isLinkedAttribution: false,
      ),
    ];

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
        ],
        child: const MaterialApp(home: TideHomeScreen()),
      ),
    );
    // Explicit pumps, not pumpAndSettle: the aurora and the hero's slow zoom
    // never stop, so the frame queue never drains.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Hero — the most-completed series (Omniscient Reader, 158/180) leads.
    expect(find.text('Omniscient Reader'), findsWidgets);
    expect(find.textContaining('MOST READ'), findsOneWidget);

    // Continue rail: both history entries resolve against the library, and
    // the caption carries the chapter plus how far through the series it is.
    expect(find.text('CONTINUE'), findsOneWidget);
    expect(find.text('Chapter 42 · 63%'), findsOneWidget);

    // The rail is populated, so its empty note must not be showing.
    expect(find.text('Nothing part-read right now.'), findsNothing);

    // Tonight sits below the fold; the list builds lazily, so scroll to it.
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('TONIGHT'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
  });

  test('tideRelative renders the design\'s compact stamps', () {
    final now = DateTime(2026, 7, 26, 12);
    expect(tideRelative(now.subtract(const Duration(minutes: 30)), now),
        '30m ago');
    expect(tideRelative(now.subtract(const Duration(hours: 4)), now), '4h ago');
    expect(
        tideRelative(now.subtract(const Duration(days: 1)), now), 'Yesterday');
    expect(tideRelative(now.subtract(const Duration(days: 8)), now),
        '1 week ago');
  });

  test('tideChapterLabel prefers the source name and falls back to a number',
      () {
    expect(tideChapterLabel('Ch. 42 — The Duel', 42), 'Ch. 42 — The Duel');
    expect(tideChapterLabel('', 42), 'Chapter 42');
    expect(tideChapterLabel('   ', 42.5), 'Chapter 42.5');
    expect(tideChapterLabel('', -1), 'Chapter');
  });
}
