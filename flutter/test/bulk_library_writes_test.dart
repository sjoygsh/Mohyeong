import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';

/// The same shape as `bulk_chapter_writes_test`, for the library's selection
/// actions. "Remove from library" ran `setFavorite` + `setCategoriesForManga`
/// once per selected entry: each is its own commit, and the ported
/// `update_last_modified_at_mangas` trigger (plus the one on
/// `mangas_categories`, which bumps `mangas.version`) makes every row write
/// re-run `libraryView` for each live subscriber — so removing a large
/// selection re-queried the grid the user was watching once per entry while it
/// worked down the list.
///
/// Counting emissions of a live `watchFavorites` is the same non-vacuity check
/// pass 8 used: with the per-row loop these come back as 40 and 20.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MangaRepository mangas;
  late CategoryRepository categories;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mangas = MangaRepository(db);
    categories = CategoryRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seedManga(int id) async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (?1, 7, 'manga/' || ?1, 'Manga ' || ?1, 0, 1, 1, 0, 0, 0, 0)",
      [id],
    );
  }

  test('un-favouriting a selection wakes the grid once, not forty times',
      () async {
    final ids = [for (var i = 1; i <= 40; i++) i];
    for (final id in ids) {
      await seedManga(id);
    }

    final emissions = <int>[];
    final sub = mangas.watchFavorites().listen((rows) {
      emissions.add(rows.length);
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions, [40]);

    await mangas.setFavoriteForIds(ids, false);
    await pumpEventQueue();

    expect(emissions, [40, 0]);
    expect(await mangas.getFavorites(), isEmpty);
  });

  test('clearing a selection\'s categories wakes it once too', () async {
    final ids = [for (var i = 1; i <= 20; i++) i];
    final catId = await categories.insert(name: 'Reading', order: 0, flags: 0);
    for (final id in ids) {
      await seedManga(id);
      await categories.setCategoriesForManga(id, {catId});
    }
    expect(await categories.getMangaIdsInCategory(catId), hasLength(20));

    // Counted straight off drift's invalidation broadcast: that is what wakes
    // every live query reading the table, and it is the cost being measured.
    var wakeups = 0;
    final sub = db
        .tableUpdates(TableUpdateQuery.onTable(db.mangasCategories))
        .listen((_) => wakeups++);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await categories.clearCategoriesForManga(ids);
    await pumpEventQueue();

    // One transaction, one broadcast. The loop this replaces made twenty.
    expect(wakeups, 1);
    expect(await categories.getMangaIdsInCategory(catId), isEmpty);
  });

  test('getByIds returns the rows that exist and skips the ones that do not',
      () async {
    await seedManga(1);
    await seedManga(2);
    final found = await mangas.getByIds([1, 2, 999]);
    expect(found.map((m) => m.id).toSet(), {1, 2});
    expect(await mangas.getByIds(const <int>[]), isEmpty);
  });
}
