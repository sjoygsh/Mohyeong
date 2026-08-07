import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/manga/scanlator_priority_repository.dart';
import 'package:mohyeong/data/backup/backup_creator.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/excluded_scanlators_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/source/source_repository.dart';
import 'package:mohyeong/data/track/track_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [BackupCreator] used to run five queries per favourite, and sync calls
/// `create()` on every cycle. It now runs five queries TOTAL and groups the
/// rows in memory. These tests pin the behaviour that made that safe: each
/// manga must still get exactly its own chapters, history, tracks, categories
/// and excluded scanlators — a grouping bug would quietly swap them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BackupCreator creator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    creator = BackupCreator(
      database: db,
      mangaRepository: MangaRepository(db),
      chapterRepository: ChapterRepository(db),
      categoryRepository: CategoryRepository(db),
      historyRepository: HistoryRepository(db),
      trackRepository: TrackRepository(db),
      sourceRepository: SourceRepository(db),
      excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
        scanlatorPriorityRepository: ScanlatorPriorityRepository(db),
    );
  });

  tearDown(() async => db.close());

  Future<void> seedManga(int id, {required bool favorite}) async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      'VALUES (?1, 7, ?2, ?3, 0, ?4, 1, 0, 0, 0, 0)',
      [id, 'manga/$id', 'Manga $id', favorite ? 1 : 0],
    );
  }

  Future<void> seedChapter(int id, int mangaId, {int order = 0}) async {
    await db.customStatement(
      'INSERT INTO chapters (_id, manga_id, url, name, read, bookmark, '
      'last_page_read, chapter_number, source_order, date_fetch, date_upload) '
      'VALUES (?1, ?2, ?3, ?4, 0, 0, 0, ?5, ?6, 0, 0)',
      [id, mangaId, 'ch/$id', 'Chapter $id', order.toDouble(), order],
    );
  }

  test('each manga gets its own chapters, history, tracks and exclusions',
      () async {
    await seedManga(1, favorite: true);
    await seedManga(2, favorite: true);
    // A non-favourite, so the bulk queries have rows they must NOT pick up.
    await seedManga(3, favorite: false);

    await seedChapter(11, 1, order: 0);
    await seedChapter(12, 1, order: 1);
    await seedChapter(21, 2, order: 0);
    await seedChapter(31, 3, order: 0);

    // History hangs off chapters, not manga — the join is where a grouping
    // bug would attribute one series' reading to another.
    await HistoryRepository(db).upsert(
      chapterId: 12,
      readAt: DateTime.fromMillisecondsSinceEpoch(5000),
      timeReadMs: 90,
    );
    await HistoryRepository(db).upsert(
      chapterId: 21,
      readAt: DateTime.fromMillisecondsSinceEpoch(6000),
      timeReadMs: 30,
    );

    await ExcludedScanlatorsRepository(db).setForManga(1, {'Ghost Scans'});
    await ExcludedScanlatorsRepository(db).setForManga(2, {'Other Scans'});

    final backup = await creator.create();
    final byTitle = {for (final m in backup.backupManga) m.title: m};

    expect(byTitle.keys, unorderedEquals(['Manga 1', 'Manga 2']));

    expect(
      byTitle['Manga 1']!.chapters.map((c) => c.url),
      // Ordered by source_order, same as the per-manga query it replaced.
      ['ch/11', 'ch/12'],
    );
    expect(byTitle['Manga 2']!.chapters.map((c) => c.url), ['ch/21']);

    expect(byTitle['Manga 1']!.history.map((h) => h.url), ['ch/12']);
    expect(byTitle['Manga 2']!.history.map((h) => h.url), ['ch/21']);

    expect(byTitle['Manga 1']!.excludedScanlators, ['Ghost Scans']);
    expect(byTitle['Manga 2']!.excludedScanlators, ['Other Scans']);
  });

  test('category membership maps to exported indices per manga', () async {
    final categories = CategoryRepository(db);
    final action = await categories.insert(name: 'Action', order: 0, flags: 0);
    final done = await categories.insert(name: 'Done', order: 1, flags: 0);

    await seedManga(1, favorite: true);
    await seedManga(2, favorite: true);
    await categories.setCategoriesForManga(1, {action, done});
    await categories.setCategoriesForManga(2, {done});

    final backup = await creator.create();
    final byTitle = {for (final m in backup.backupManga) m.title: m};
    final indexOf = {
      for (var i = 0; i < backup.backupCategories.length; i++)
        backup.backupCategories[i].name: i,
    };

    expect(
      byTitle['Manga 1']!.categories,
      unorderedEquals([indexOf['Action'], indexOf['Done']]),
    );
    expect(byTitle['Manga 2']!.categories, [indexOf['Done']]);
  });

  test('a favourite with nothing attached still exports', () async {
    await seedManga(1, favorite: true);
    final backup = await creator.create();
    expect(backup.backupManga, hasLength(1));
    expect(backup.backupManga.single.chapters, isEmpty);
    expect(backup.backupManga.single.history, isEmpty);
    expect(backup.backupManga.single.tracking, isEmpty);
    expect(backup.backupManga.single.categories, isEmpty);
    expect(backup.backupManga.single.excludedScanlators, isEmpty);
  });
}
