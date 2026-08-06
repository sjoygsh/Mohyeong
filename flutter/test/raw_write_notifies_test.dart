import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';

/// Drift refreshes a live query when one of the tables it reads is written
/// THROUGH DRIFT. A raw `customStatement` is opaque to it: the rows change and
/// nothing on screen hears about it. Two writes in this app are raw for good
/// reasons of their own, and both have to announce themselves by hand.
///
/// The failure mode is quiet and remote from the cause — a sync pulls another
/// device's reading progress and the History tab goes on showing yesterday —
/// so it is pinned here rather than left to be noticed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed({required bool favorite}) async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (1, 7, 'manga/1', 'Manga', 0, ?1, 1, 0, 0, 0, 0)",
      [favorite ? 1 : 0],
    );
    await db.customStatement(
      'INSERT INTO chapters (_id, manga_id, url, name, read, bookmark, '
      'last_page_read, chapter_number, source_order, date_fetch, date_upload) '
      "VALUES (10, 1, 'ch/10', 'Chapter 1', 0, 0, 0, 1, 0, 0, 0)",
    );
  }

  test('a synced-in history row reaches a live history query', () async {
    await seed(favorite: true);
    final repo = HistoryRepository(db);

    final seen = <int>[];
    final sub = repo.watchRecent().listen((rows) => seen.add(rows.length));
    await pumpEventQueue();
    expect(seen, [0]);

    // What backup restore and cross-device sync call.
    await repo.upsertAbsolute(
      chapterId: 10,
      readAtMs: 1700000000000,
      timeReadMs: 5000,
    );
    await pumpEventQueue();

    expect(seen, [0, 1], reason: 'the feed must see the synced-in row');
    await sub.cancel();
  });

  test('clearing non-library entries reaches a live chapter query', () async {
    await seed(favorite: false);

    final seen = <int>[];
    final sub = db
        .select(db.chapters)
        .watch()
        .listen((rows) => seen.add(rows.length));
    await pumpEventQueue();
    expect(seen, [1]);

    // Deletes the dependent rows with raw statements, then the manga itself.
    final removed = await MangaRepository(db).clearNonLibraryEntries();
    await pumpEventQueue();

    expect(removed, 1);
    expect(seen, [1, 0], reason: 'the emptied chapter table must be reported');
    await sub.cancel();
  });
}
