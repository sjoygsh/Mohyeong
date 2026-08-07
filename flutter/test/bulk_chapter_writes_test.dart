import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';

/// Bulk mark-read used to write one row at a time.
///
/// Two costs, and the second is the one that hurt: each write was its own
/// implicit commit, and each fired drift's `chapters` invalidation, so every
/// live query in the app re-ran ONCE PER CHAPTER. Marking a long series read
/// from the library grid therefore re-ran the whole-library aggregate, the
/// updates join and History's recent-reads join hundreds of times for a single
/// tap.
///
/// These tests pin the shape that fixes it: one transaction, one notification,
/// and a query that hands back only the rows the write would actually change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChapterRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ChapterRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seedManga(int id) async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (?1, 7, 'manga/?1', 'Manga', 0, 1, 1, 0, 0, 0, 0)",
      [id],
    );
  }

  Future<void> seedChapter(
    int id,
    int mangaId, {
    int read = 0,
    int lastPageRead = 0,
    int bookmark = 0,
  }) async {
    await db.customStatement(
      'INSERT INTO chapters (_id, manga_id, url, name, read, bookmark, '
      'last_page_read, chapter_number, source_order, date_fetch, date_upload) '
      "VALUES (?1, ?2, 'ch/?1', 'Chapter', ?3, ?4, ?5, 1, 0, 0, 0)",
      [id, mangaId, read, bookmark, lastPageRead],
    );
  }

  test('a batch of read flips lands in ONE stream notification', () async {
    await seedManga(1);
    for (var i = 1; i <= 40; i++) {
      await seedChapter(i, 1);
    }

    final emissions = <int>[];
    final sub = repo
        .watchByMangaId(1)
        .listen((rows) => emissions.add(rows.where((c) => c.read).length));
    await pumpEventQueue();
    expect(emissions, [0]);

    await repo.setReadForIds(List<int>.generate(40, (i) => i + 1), true);
    await pumpEventQueue();

    // The per-row loop produced one emission per chapter. Anything above two
    // entries here means the batch is committing (and invalidating) per row
    // again.
    expect(
      emissions,
      [0, 40],
      reason: 'one transaction must invalidate the query exactly once',
    );
    await sub.cancel();
  });

  test('setReadForIds clears the saved page only when marking unread',
      () async {
    await seedManga(1);
    await seedChapter(1, 1, read: 0, lastPageRead: 12);
    await seedChapter(2, 1, read: 1, lastPageRead: 30);

    await repo.setReadForIds([1], true);
    var rows = await repo.getByIds([1]);
    expect(rows.single.read, isTrue);
    expect(rows.single.lastPageRead, 12,
        reason: 'marking read keeps where you were');

    await repo.setReadForIds([2], false);
    rows = await repo.getByIds([2]);
    expect(rows.single.read, isFalse);
    expect(rows.single.lastPageRead, 0,
        reason: 'marking unread resets the position');
  });

  test('setBookmarkForIds flips a whole batch', () async {
    await seedManga(1);
    for (var i = 1; i <= 5; i++) {
      await seedChapter(i, 1);
    }
    await repo.setBookmarkForIds([1, 2, 3, 4, 5], true);
    final rows = await repo.getByIds([1, 2, 3, 4, 5]);
    expect(rows.every((c) => c.bookmark), isTrue);
  });

  test('an empty batch writes nothing and notifies nothing', () async {
    await seedManga(1);
    await seedChapter(1, 1);

    final emissions = <int>[];
    final sub = repo.watchByMangaId(1).listen((rows) => emissions.add(rows.length));
    await pumpEventQueue();
    expect(emissions, [1]);

    await repo.setReadForIds(const <int>[], true);
    await repo.setBookmarkForIds(const <int>[], true);
    await pumpEventQueue();

    expect(emissions, [1]);
    await sub.cancel();
  });

  group('chaptersNeedingReadFlip', () {
    test('marking read returns only unread rows, across several manga',
        () async {
      await seedManga(1);
      await seedManga(2);
      await seedChapter(1, 1, read: 1);
      await seedChapter(2, 1, read: 0);
      await seedChapter(3, 2, read: 0);
      await seedChapter(4, 2, read: 1);

      final rows = await repo.chaptersNeedingReadFlip([1, 2], read: true);
      expect(rows.map((c) => c.id).toSet(), {2, 3});
    });

    test('marking unread returns read rows AND rows holding a page position',
        () async {
      await seedManga(1);
      await seedChapter(1, 1, read: 1);
      await seedChapter(2, 1, read: 0, lastPageRead: 7);
      await seedChapter(3, 1, read: 0);

      final rows = await repo.chaptersNeedingReadFlip([1], read: false);
      expect(
        rows.map((c) => c.id).toSet(),
        {1, 2},
        reason: 'a part-read chapter still has progress to clear',
      );
    });

    test('a fully-read selection asks for no work at all', () async {
      await seedManga(1);
      await seedChapter(1, 1, read: 1);
      await seedChapter(2, 1, read: 1);

      expect(await repo.chaptersNeedingReadFlip([1], read: true), isEmpty);
      expect(await repo.chaptersNeedingReadFlip(const <int>[], read: true),
          isEmpty);
    });
  });
}
