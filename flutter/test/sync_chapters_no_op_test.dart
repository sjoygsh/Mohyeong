import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/domain/source/model/source_chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sync that finds nothing new used to rewrite EVERY existing row. The cost
/// was the smaller half: `chapters` carries an AFTER UPDATE trigger that sets
/// `last_modified_at`, and that column is what cross-device sync reads to
/// decide what changed — so a library update told sync the entire series had
/// been edited, every time, for every series.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChapterRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ChapterRepository(db);
    await db.customInsert(
      'INSERT INTO mangas(_id,source,url,title,status,favorite,initialized,'
      'viewer,chapter_flags,cover_last_modified,date_added) '
      'VALUES(1,1,"/m1","M1",0,1,0,0,0,0,0)',
    );
  });

  tearDown(() async => db.close());

  SourceChapter sc(int i, {String? name, double? number}) => SourceChapter(
        url: '/c$i',
        name: name ?? 'Chapter $i',
        dateUpload: 0,
        chapterNumber: number ?? i.toDouble(),
        volumeNumber: null,
        scanlator: null,
      );

  /// Rows written since the connection opened, triggers included. A sentinel
  /// column can't be used here: stamping one fires the very AFTER UPDATE
  /// trigger under test, which overwrites it.
  Future<int> writes() async {
    final row = await db
        .customSelect('SELECT total_changes() AS c', variables: const [])
        .getSingle();
    return row.read<int>('c');
  }

  test('re-syncing an unchanged list writes nothing', () async {
    final feed = [for (var i = 0; i < 5; i++) sc(i)];
    await repo.syncChaptersWithSource(1, feed);

    final before = await writes();
    await repo.syncChaptersWithSource(1, feed);
    final delta = await writes() - before;

    expect(delta, 0, reason: 'no row should have been written');
  });

  test('a row the source actually changed is still written', () async {
    final feed = [for (var i = 0; i < 5; i++) sc(i)];
    await repo.syncChaptersWithSource(1, feed);

    // One chapter gets retitled upstream; the rest are identical.
    final edited = [
      for (var i = 0; i < 5; i++)
        if (i == 2) sc(i, name: 'Chapter 2 (v2)') else sc(i),
    ];
    final before = await writes();
    await repo.syncChaptersWithSource(1, edited);
    final delta = await writes() - before;

    // The row itself plus the last_modified_at trigger's own write.
    expect(delta, 2, reason: 'exactly one row, not all five');
    final names = await db
        .customSelect(
            'SELECT name FROM chapters WHERE manga_id = 1 ORDER BY _id',
            variables: const [])
        .get();
    expect(names[2].read<String>('name'), 'Chapter 2 (v2)');
  });

  test('a reordered list writes only the rows that moved', () async {
    final feed = [for (var i = 0; i < 5; i++) sc(i)];
    await repo.syncChaptersWithSource(1, feed);

    // The source swaps the last two — sourceOrder changes for those only.
    final reordered = [sc(0), sc(1), sc(2), sc(4), sc(3)];
    final before = await writes();
    await repo.syncChaptersWithSource(1, reordered);
    final delta = await writes() - before;

    expect(delta, 4, reason: 'two rows, each plus its trigger write');
  });
}
