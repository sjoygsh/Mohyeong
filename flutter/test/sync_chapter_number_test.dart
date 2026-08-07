import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/domain/source/model/source_chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kotlin `SyncChaptersWithSource` derives every chapter's number from its name
/// when the source didn't give one. This port stored what the extension sent —
/// and both shared theme factories in `_mhThemeLib` send a literal
/// `chapter_number: -1`, so most of the library had -1 in that column for every
/// row, and everything keyed on it (sort by chapter number, gap detection,
/// linked-source merging, the duplicate-chapter rules that all test
/// `chapterNumber >= 0`) silently did nothing.
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
      'VALUES(1,1,"/m1","Solo Leveling",0,1,0,0,0,0,0)',
    );
  });

  tearDown(() async => db.close());

  SourceChapter sc(String url, String name, double number) => SourceChapter(
        url: url,
        name: name,
        dateUpload: 0,
        chapterNumber: number,
        volumeNumber: null,
        scanlator: null,
      );

  test('a source that numbers nothing still gets numbered chapters', () async {
    await repo.syncChaptersWithSource(1, [
      sc('/c1', 'Chapter 1', -1),
      sc('/c2', 'Chapter 2.5', -1),
      sc('/c3', 'Solo Leveling Vol.2 Ch. 12: The Rematch', -1),
      sc('/c4', 'Chapter 13 extra', -1),
    ]);

    final rows = await repo.getByMangaId(1);
    final byUrl = {for (final c in rows) c.url: c.chapterNumber};
    // Every one of these was -1 before.
    expect(byUrl['/c1'], 1.0);
    expect(byUrl['/c2'], 2.5);
    expect(byUrl['/c3'], 12.0);
    expect(byUrl['/c4'], 13.99);
  });

  test('a number the source DID supply is left exactly as it was', () async {
    await repo.syncChaptersWithSource(1, [
      sc('/c1', 'Some unparseable name', 41.0),
      sc('/c2', 'Chapter 99', 7.0),
    ]);

    final byUrl = {
      for (final c in await repo.getByMangaId(1)) c.url: c.chapterNumber,
    };
    expect(byUrl['/c1'], 41.0);
    expect(byUrl['/c2'], 7.0, reason: 'the name must not override the source');
  });

  test('a name with no number in it stays at -1', () async {
    await repo.syncChaptersWithSource(1, [sc('/c1', 'Prologue', -1)]);
    expect((await repo.getByMangaId(1)).single.chapterNumber, -1.0);
  });

  test('re-syncing the same feed still writes nothing', () async {
    // The derived number has to be stable, or every sweep would rewrite every
    // row and tell cross-device sync the whole series had been edited — the
    // regression `sync_chapters_no_op_test` exists to prevent.
    final feed = [
      sc('/c1', 'Chapter 1', -1),
      sc('/c2', 'Chapter 2', -1),
    ];
    await repo.syncChaptersWithSource(1, feed);
    final before = await db
        .customSelect('SELECT total_changes() AS c')
        .getSingle()
        .then((r) => r.read<int>('c'));
    await repo.syncChaptersWithSource(1, feed);
    final after = await db
        .customSelect('SELECT total_changes() AS c')
        .getSingle()
        .then((r) => r.read<int>('c'));
    expect(after, before);
  });
}
