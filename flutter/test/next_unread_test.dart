import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';

/// Resume, "download the next N" and the feeds' bulk mark-read used to read a
/// whole series to answer a question about a few of its rows. They now ask for
/// what they want, which only helps if the answers are identical — and the
/// direction is the easy thing to get backwards, because `sourceOrder` 0 is
/// the NEWEST chapter, so reading order is descending.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChapterRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ChapterRepository(db);
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (1, 7, 'manga/1', 'Manga', 0, 1, 1, 0, 0, 0, 0)",
    );
  });

  tearDown(() => db.close());

  /// [order] 0 is the newest chapter.
  Future<void> chapter(int id, {required int order, required bool read}) =>
      db.customStatement(
        'INSERT INTO chapters (_id, manga_id, url, name, read, bookmark, '
        'last_page_read, chapter_number, source_order, date_fetch, '
        'date_upload) VALUES (?1, 1, ?2, ?3, ?4, 0, 0, ?5, ?6, 0, 0)',
        [id, 'ch/$id', 'Chapter $id', read ? 1 : 0, order.toDouble(), order],
      );

  test('resume opens the oldest unread chapter, not the newest', () async {
    await chapter(1, order: 0, read: false); // newest, unread
    await chapter(2, order: 1, read: false);
    await chapter(3, order: 2, read: false); // oldest unread
    await chapter(4, order: 3, read: true); // older still, already read

    expect((await repo.nextUnread(1))!.id, 3);
  });

  test('a fully read series has nothing to resume', () async {
    await chapter(1, order: 0, read: true);
    await chapter(2, order: 1, read: true);

    expect(await repo.nextUnread(1), isNull);
  });

  test('"next N" takes the N oldest unread, in reading order', () async {
    for (var i = 0; i < 6; i++) {
      await chapter(i + 1, order: i, read: i >= 4);
    }
    // Unread are orders 0..3; reading order is 3, 2, 1, 0.
    final next2 = await repo.unreadInReadingOrder(1, limit: 2);
    expect(next2.map((c) => c.sourceOrder), [3, 2]);

    final all = await repo.unreadInReadingOrder(1);
    expect(all.map((c) => c.sourceOrder), [3, 2, 1, 0]);
  });

  test('getByIds returns exactly the asked-for rows and nothing else',
      () async {
    await chapter(1, order: 0, read: false);
    await chapter(2, order: 1, read: false);
    await chapter(3, order: 2, read: false);

    final picked = await repo.getByIds([1, 3]);
    expect(picked.map((c) => c.id).toSet(), {1, 3});
    expect(await repo.getByIds(const <int>[]), isEmpty);
  });

  test('one series\' chapters never leak into another\'s answers', () async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (2, 7, 'manga/2', 'Other', 0, 1, 1, 0, 0, 0, 0)",
    );
    await chapter(1, order: 0, read: true);
    await db.customStatement(
      'INSERT INTO chapters (_id, manga_id, url, name, read, bookmark, '
      'last_page_read, chapter_number, source_order, date_fetch, date_upload) '
      "VALUES (99, 2, 'ch/99', 'Other ch', 0, 0, 0, 0, 0, 0, 0)",
    );

    expect(await repo.nextUnread(1), isNull);
    expect((await repo.nextUnread(2))!.id, 99);
  });
}
