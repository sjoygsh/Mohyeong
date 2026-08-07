import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/backup/backup_restorer.dart';
import 'package:mohyeong/data/backup/models/backup_models.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/excluded_scanlators_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/source/source_repository.dart';
import 'package:mohyeong/data/track/track_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A category's `parent_id` is a LOCAL row id, and a restored category does
/// not keep the id it had on the device the backup came from. The restorer
/// used to copy the backup's raw parent id into the new row, which pointed
/// each nested category at whatever local category happened to occupy that
/// id — an unrelated category, itself, or nothing at all. Kotlin's
/// `CategoriesRestorer` remaps in a second pass; these pin that it does here
/// too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BackupRestorer restorer;
  late CategoryRepository categories;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categories = CategoryRepository(db);
    restorer = BackupRestorer(
      database: db,
      mangaRepository: MangaRepository(db),
      chapterRepository: ChapterRepository(db),
      categoryRepository: categories,
      historyRepository: HistoryRepository(db),
      trackRepository: TrackRepository(db),
      sourceRepository: SourceRepository(db),
      excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, ({int id, int? parentId, int order})>> byName() async {
    final all = await categories.getAll();
    return {
      for (final c in all)
        c.name: (id: c.id, parentId: c.parentId, order: c.order),
    };
  }

  test('a nested category is reparented to its parent\'s NEW local id',
      () async {
    // Ids 40/41 are this backup's own row ids; nothing local uses them.
    await restorer.restore(Backup(backupCategories: [
      BackupCategory(name: 'Manga', order: 0, id: 40),
      BackupCategory(name: 'Ongoing', order: 1, id: 41, parentId: 40),
    ]));

    final cats = await byName();
    expect(cats['Ongoing']!.parentId, cats['Manga']!.id);
    expect(cats['Manga']!.parentId, isNull);
    // The whole point: the id it was written with is NOT the id it had in
    // the backup, so copying the raw value could not have been right.
    expect(cats['Manga']!.id, isNot(40));
  });

  test('a parent that resolves to an existing local category is respected',
      () async {
    final localId = await categories.insert(name: 'Manga', order: 0, flags: 0);

    await restorer.restore(Backup(backupCategories: [
      BackupCategory(name: 'Manga', order: 0, id: 7),
      BackupCategory(name: 'Ongoing', order: 1, id: 8, parentId: 7),
    ]));

    final cats = await byName();
    expect(cats['Ongoing']!.parentId, localId,
        reason: 'matched-by-name categories are reused, not duplicated');
    expect(cats.keys.where((k) => k == 'Manga').length, 1);
  });

  test('a parent not present in the backup leaves the category top-level',
      () async {
    await restorer.restore(Backup(backupCategories: [
      BackupCategory(name: 'Orphan', order: 0, id: 3, parentId: 999),
    ]));

    expect((await byName())['Orphan']!.parentId, isNull);
  });

  test('a self-parenting category is not allowed to point at itself',
      () async {
    await restorer.restore(Backup(backupCategories: [
      BackupCategory(name: 'Loop', order: 0, id: 5, parentId: 5),
    ]));

    final loop = (await byName())['Loop']!;
    expect(loop.parentId, isNot(loop.id));
    expect(loop.parentId, isNull);
  });

  test('restored orders continue past the local maximum instead of colliding',
      () async {
    await categories.insert(name: 'Local A', order: 0, flags: 0);
    await categories.insert(name: 'Local B', order: 1, flags: 0);

    await restorer.restore(Backup(backupCategories: [
      // Both orders collide with the local categories above.
      BackupCategory(name: 'From backup 1', order: 0, id: 1),
      BackupCategory(name: 'From backup 2', order: 1, id: 2),
    ]));

    final cats = await byName();
    final orders = cats.values.map((c) => c.order).toList()..sort();
    expect(
      orders.toSet().length,
      orders.length,
      reason: 'every category must keep a distinct sort position',
    );
    expect(cats['From backup 1']!.order, greaterThan(cats['Local B']!.order));
    // The backup's own order still decides the sequence they are created in.
    expect(
      cats['From backup 1']!.order,
      lessThan(cats['From backup 2']!.order),
    );
  });

  test('manga category membership still resolves by input index', () async {
    // The returned id list indexes `BackupManga.categories`, so sorting the
    // insert pass by order must not disturb it. Backup order is deliberately
    // the reverse of list order here.
    await restorer.restore(Backup(
      backupCategories: [
        BackupCategory(name: 'Second', order: 9, id: 1),
        BackupCategory(name: 'First', order: 0, id: 2),
      ],
      backupManga: [
        BackupManga(
          source: 1,
          url: 'manga/1',
          title: 'Manga',
          favorite: true,
          // Index 1 == 'First'.
          categories: [1],
        ),
      ],
    ));

    final cats = await byName();
    final manga = await MangaRepository(db).getByUrlAndSource('manga/1', 1);
    final memberships =
        await categories.getCategoryIdsForManga(manga!.id);
    expect(memberships, {cats['First']!.id});
  });
}
