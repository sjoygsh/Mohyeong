import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/domain/source/model/source_chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for [ChapterRepository.syncChaptersWithSource] after it
/// switched from a per-row insert loop to one batched insertAll + id re-query.
/// The correctness-sensitive contract: the returned `added` list (which feeds
/// the Updates tab / auto-download) carries the real DB ids, is in fetched
/// order, excludes mark-duplicate-read inserts, and re-sync preserves local
/// read/bookmark state without creating duplicate rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChapterRepository repo;

  Future<int> seedManga() async {
    await db.customInsert(
      'INSERT INTO mangas(_id,source,url,title,status,favorite,initialized,'
      'viewer,chapter_flags,cover_last_modified,date_added) '
      'VALUES(1,1,?,?,0,0,0,0,0,0,0)',
      variables: [Variable('manga-url'), Variable('Test Manga')],
    );
    return 1;
  }

  SourceChapter ch(String url, String name, {double number = -1, int date = 0}) =>
      SourceChapter(url: url, name: name, chapterNumber: number, dateUpload: date);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh sync batch-inserts every chapter, in fetched order, with real ids',
      () async {
    repo = ChapterRepository(db);
    final mangaId = await seedManga();
    final fetched = [
      ch('c/3', 'Chapter 3', number: 3),
      ch('c/2', 'Chapter 2', number: 2),
      ch('c/1', 'Chapter 1', number: 1),
    ];

    final added = await repo.syncChaptersWithSource(mangaId, fetched);

    // All three are new → all returned, in fetched order.
    expect(added.map((c) => c.url), ['c/3', 'c/2', 'c/1']);
    // Every returned chapter carries a real (>0) persisted id, matching the DB.
    final stored = await repo.getByMangaId(mangaId);
    final idByUrl = {for (final c in stored) c.url: c.id};
    for (final a in added) {
      expect(a.id, greaterThan(0));
      expect(a.id, idByUrl[a.url]);
    }
    // sourceOrder mirrors the fetched index.
    expect(stored.length, 3);
    expect(stored.firstWhere((c) => c.url == 'c/3').sourceOrder, 0);
    expect(stored.firstWhere((c) => c.url == 'c/1').sourceOrder, 2);
  });

  test('re-sync returns no new chapters, updates in place, preserves read state',
      () async {
    repo = ChapterRepository(db);
    final mangaId = await seedManga();
    await repo.syncChaptersWithSource(mangaId, [
      ch('c/1', 'Chapter 1', number: 1),
      ch('c/2', 'Chapter 2', number: 2),
    ]);
    // Mark chapter 1 read.
    final c1 = (await repo.getByMangaId(mangaId)).firstWhere((c) => c.url == 'c/1');
    await repo.setRead(c1.id, true);

    // Re-sync with a renamed chapter 2 + same chapter 1.
    final added = await repo.syncChaptersWithSource(mangaId, [
      ch('c/1', 'Chapter 1', number: 1),
      ch('c/2', 'Chapter 2 (v2)', number: 2),
    ]);

    expect(added, isEmpty); // nothing new
    final stored = await repo.getByMangaId(mangaId);
    expect(stored.length, 2); // no duplicate rows
    expect(stored.firstWhere((c) => c.url == 'c/1').read, isTrue); // read kept
    expect(stored.firstWhere((c) => c.url == 'c/2').name, 'Chapter 2 (v2)');
    // The read row kept its id (updated, not re-inserted).
    expect(stored.firstWhere((c) => c.url == 'c/1').id, c1.id);
  });

  test('chapters missing from the new fetch are deleted', () async {
    repo = ChapterRepository(db);
    final mangaId = await seedManga();
    await repo.syncChaptersWithSource(mangaId, [
      ch('c/1', 'Chapter 1', number: 1),
      ch('c/2', 'Chapter 2', number: 2),
      ch('c/3', 'Chapter 3', number: 3),
    ]);

    await repo.syncChaptersWithSource(mangaId, [
      ch('c/2', 'Chapter 2', number: 2),
      ch('c/3', 'Chapter 3', number: 3),
    ]);

    final urls = (await repo.getByMangaId(mangaId)).map((c) => c.url).toSet();
    expect(urls, {'c/2', 'c/3'});
  });

  test('mark-duplicate-read inserts the new chapter read and omits it from added',
      () async {
    SharedPreferences.setMockInitialValues({
      'mark_duplicate_read_chapter_read': <String>['new'],
    });
    repo = ChapterRepository(db);
    final mangaId = await seedManga();
    // Seed + read chapter 5.
    await repo.syncChaptersWithSource(mangaId, [ch('c/5', 'Chapter 5', number: 5)]);
    final c5 = (await repo.getByMangaId(mangaId)).single;
    await repo.setRead(c5.id, true);

    // A new chapter with the SAME number 5 (e.g. a re-upload at a new URL).
    final added = await repo.syncChaptersWithSource(mangaId, [
      ch('c/5', 'Chapter 5', number: 5),
      ch('c/5-dup', 'Chapter 5 dup', number: 5),
      ch('c/6', 'Chapter 6', number: 6),
    ]);

    // The duplicate-numbered new chapter is excluded from `added`; chapter 6 is not.
    expect(added.map((c) => c.url), ['c/6']);
    final stored = await repo.getByMangaId(mangaId);
    // It was still inserted, and inserted as read.
    expect(stored.firstWhere((c) => c.url == 'c/5-dup').read, isTrue);
  });
}
