import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/main.dart';

class _FakeMangaRepository implements MangaRepository {
  @override
  Stream<List<Manga>> watchFavorites() => Stream.value(const <Manga>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  Future<int> totalReadDurationMs() async => 0;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Home shell renders all five top-level tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mangaRepositoryProvider.overrideWithValue(_FakeMangaRepository()),
          historyRepositoryProvider.overrideWithValue(_FakeHistoryRepository()),
        ],
        child: const MohyeongApp(),
      ),
    );
    // Two pumps -- one for first frame, one to let the empty-state StreamBuilder
    // resolve its first event.
    await tester.pump();

    // AppBar title for the default (Library) tab.
    expect(find.text('Library'), findsWidgets);
    // The other four tab labels should be present in the NavigationBar.
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // The library should be in its empty state since the fake repo returns [].
    expect(find.text('Your library is empty.'), findsOneWidget);
  });
}
