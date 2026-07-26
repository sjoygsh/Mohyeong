import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/source/extension_repository.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/source/model/manga_source.dart';
import 'package:mohyeong/domain/source/model/source_manga.dart';
import 'package:mohyeong/presentation/browse/source_browse_screen.dart';
import 'package:mohyeong/presentation/tide/tide.dart';

/// Popular / Latest / Search each hit the network on their first build, so
/// which of them get BUILT is a question about how many requests opening a
/// source fires at it. An IndexedStack builds every child by default; this
/// asserts the screen doesn't.

class _FakeSource implements MangaSource {
  _FakeSource({this.supportsLatest = true});

  int popularCalls = 0;
  int latestCalls = 0;
  int filterCalls = 0;

  @override
  final bool supportsLatest;

  @override
  String get id => 'fake';

  @override
  String get name => 'Fake Scans';

  @override
  String get lang => 'en';

  @override
  String get baseUrl => 'https://fake.example';

  MangasPage _page(String prefix) => MangasPage(
        mangas: [
          for (var i = 1; i <= 3; i++)
            SourceManga(url: '/$prefix/$i', title: '$prefix $i'),
        ],
        hasNextPage: false,
      );

  @override
  Future<MangasPage> fetchPopular(int page) async {
    popularCalls++;
    return _page('Popular');
  }

  @override
  Future<MangasPage> fetchLatest(int page) async {
    latestCalls++;
    return _page('Latest');
  }

  @override
  Future<List<SourceFilterDef>> getFilters() async {
    filterCalls++;
    return const [];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExtensionRepository implements ExtensionRepository {
  _FakeExtensionRepository(this.source);

  final MangaSource source;

  @override
  Future<MangaSource> getSource(String id) async => source;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMangaRepository implements MangaRepository {
  @override
  Future<List<Manga>> getFavoritesBySource(int sourceId) async =>
      const <Manga>[];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_FakeSource> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final source = _FakeSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        extensionRepositoryProvider
            .overrideWithValue(_FakeExtensionRepository(source)),
        mangaRepositoryProvider.overrideWithValue(_FakeMangaRepository()),
      ],
      child: const MaterialApp(home: SourceBrowseScreen(sourceId: 'fake')),
    ),
  );
  await _pump(tester);
  return source;
}

void main() {
  testWidgets('opening a source fetches Popular only', (tester) async {
    final source = await _open(tester);

    expect(find.text('Fake Scans'), findsOneWidget);
    expect(find.byType(TideSegmented), findsOneWidget);
    expect(source.popularCalls, 1);
    // The regression this pins: Latest and Search must not have been built,
    // so the source is asked for one page, not three things.
    expect(source.latestCalls, 0);
    expect(source.filterCalls, 0);
    expect(find.text('Popular 1'), findsOneWidget);
  });

  testWidgets('each view fetches when it is first opened, once',
      (tester) async {
    final source = await _open(tester);

    await tester.tap(find.text('Latest'));
    await _pump(tester);
    expect(source.latestCalls, 1);
    expect(find.text('Latest 1'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await _pump(tester);
    expect(source.filterCalls, 1);
    expect(find.text('Enter a query to search.'), findsOneWidget);

    // Going back to a view already built must not re-fetch it: the pages it
    // loaded are still there.
    await tester.tap(find.text('Popular'));
    await _pump(tester);
    expect(source.popularCalls, 1);
    expect(source.latestCalls, 1);
    expect(find.text('Popular 1'), findsOneWidget);
  });
}
