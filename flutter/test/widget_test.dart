import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/source/extension_repository.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/data/updates/updates_repository.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/source/model/manga_source.dart';
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
  Stream<List<HistoryWithContext>> watchRecent({int limit = 200}) =>
      Stream.value(const <HistoryWithContext>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUpdatesRepository implements UpdatesRepository {
  @override
  Stream<List<LibraryUpdate>> watchAll() =>
      Stream.value(const <LibraryUpdate>[]);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExtensionRepository implements ExtensionRepository {
  @override
  Stream<List<InstalledExtension>> watchInstalled() =>
      Stream.value(const <InstalledExtension>[]);

  @override
  Future<List<InstalledExtension>> listInstalled() async =>
      const <InstalledExtension>[];

  @override
  Future<MangaSource> getSource(String id) async =>
      throw UnimplementedError();

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
          updatesRepositoryProvider.overrideWithValue(_FakeUpdatesRepository()),
          extensionRepositoryProvider
              .overrideWithValue(_FakeExtensionRepository()),
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
