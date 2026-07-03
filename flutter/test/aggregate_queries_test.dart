import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract coverage for the grouped aggregates that replaced the library
/// updater's per-manga N+1 lookups: the maps must agree with what the
/// old per-manga queries would have reported.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedManga(int id, String url) => db.customInsert(
        'INSERT INTO mangas(_id,source,url,title,status,favorite,initialized,'
        'viewer,chapter_flags,cover_last_modified,date_added) '
        'VALUES(?,1,?,?,0,1,0,0,0,0,0)',
        variables: [Variable(id), Variable(url), Variable('M$id')],
      );

  Future<void> seedChapter(int mangaId, String url, {required bool read}) =>
      db.customInsert(
        'INSERT INTO chapters(manga_id,url,name,read,bookmark,last_page_read,'
        'chapter_number,source_order,date_fetch,date_upload) '
        'VALUES(?,?,?,?,0,0,-1,0,0,0)',
        variables: [
          Variable(mangaId),
          Variable(url),
          Variable('c'),
          Variable(read ? 1 : 0),
        ],
      );

  test('readStateCountsByManga matches per-manga chapter state', () async {
    final chapters = ChapterRepository(db);
    await seedManga(1, 'm/1');
    await seedManga(2, 'm/2');
    await seedManga(3, 'm/3'); // no chapters at all
    await seedChapter(1, 'c/1a', read: true);
    await seedChapter(1, 'c/1b', read: false);
    await seedChapter(1, 'c/1c', read: false);
    await seedChapter(2, 'c/2a', read: true);

    final counts = await chapters.readStateCountsByManga();

    expect(counts[1], (total: 3, unread: 2));
    expect(counts[2], (total: 1, unread: 0));
    expect(counts[3], isNull, reason: 'chapterless manga has no row');
  });

  test('getAllMangaCategoryIds matches per-manga membership', () async {
    final categories = CategoryRepository(db);
    await seedManga(1, 'm/1');
    await seedManga(2, 'm/2');
    final catA = await categories.insert(name: 'A', order: 0, flags: 0);
    final catB = await categories.insert(name: 'B', order: 1, flags: 0);
    await categories.setCategoriesForManga(1, {catA, catB});
    await categories.setCategoriesForManga(2, {catB});

    final all = await categories.getAllMangaCategoryIds();

    expect(all[1], {catA, catB});
    expect(all[2], {catB});
    // Parity with the single-manga path used elsewhere in the app.
    expect(all[1], await categories.getCategoryIdsForManga(1));
    expect(all[2], await categories.getCategoryIdsForManga(2));
  });
}
