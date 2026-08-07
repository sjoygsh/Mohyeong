import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/backup/backup_codec.dart';
import 'package:mohyeong/data/backup/backup_creator.dart';
import 'package:mohyeong/data/backup/backup_restorer.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/excluded_scanlators_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/manga/scanlator_priority_repository.dart';
import 'package:mohyeong/data/source/source_repository.dart';
import 'package:mohyeong/data/track/track_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `scanlator_priority` is a fork table (migration 12) that NEITHER app backs
/// up, so a per-manga scanlator ranking was lost on every export — the same
/// data-loss class as the excluded-scanlator bug already fixed, one table over.
///
/// It rides at tag 900, clear of Mihon's range, so their decoder ignores it and
/// a backup still round-trips through Mihon unharmed.
///
/// The ranking is an ORDER, not a set: position 0 is the most preferred, so the
/// test has to prove the order survives, not just the membership.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ScanlatorPriorityRepository priorities;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    priorities = ScanlatorPriorityRepository(db);
  });
  tearDown(() => db.close());

  BackupCreator creator() => BackupCreator(
        database: db,
        mangaRepository: MangaRepository(db),
        chapterRepository: ChapterRepository(db),
        categoryRepository: CategoryRepository(db),
        historyRepository: HistoryRepository(db),
        trackRepository: TrackRepository(db),
        sourceRepository: SourceRepository(db),
        excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
        scanlatorPriorityRepository: priorities,
      );

  BackupRestorer restorer() => BackupRestorer(
        database: db,
        mangaRepository: MangaRepository(db),
        chapterRepository: ChapterRepository(db),
        categoryRepository: CategoryRepository(db),
        historyRepository: HistoryRepository(db),
        trackRepository: TrackRepository(db),
        sourceRepository: SourceRepository(db),
        excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
        scanlatorPriorityRepository: priorities,
      );

  Future<void> seedFavorite(int id) async {
    await db.customStatement(
      'INSERT INTO mangas (_id, source, url, title, status, favorite, '
      'initialized, viewer, chapter_flags, cover_last_modified, date_added) '
      "VALUES (?1, 7, 'manga/' || ?1, 'Ranked', 0, 1, 1, 0, 0, 0, 0)",
      [id],
    );
  }

  test('a ranking survives export and import, in order', () async {
    await seedFavorite(1);
    const ranking = ['Alpha Scans', 'Beta Scans', 'Gamma Scans'];
    await priorities.setForManga(1, ranking);

    final backup = await creator().create();
    // Through the real bytes, so the tag has to be written AND read.
    final decoded = decodeBackup(encodeBackup(backup));
    expect(decoded.backupManga.single.scanlatorPriority, ranking);

    // Wipe it, then restore.
    await priorities.setForManga(1, const []);
    expect(await priorities.getByMangaId(1), isEmpty);

    await restorer().restore(decoded);
    expect(await priorities.getByMangaId(1), ranking,
        reason: 'position 0 is the most preferred — order is the data');
  });

  test('a manga with no ranking writes no field and restores clean', () async {
    await seedFavorite(1);
    final decoded = decodeBackup(encodeBackup(await creator().create()));
    expect(decoded.backupManga.single.scanlatorPriority, isEmpty);
    await restorer().restore(decoded);
    expect(await priorities.getByMangaId(1), isEmpty);
  });

  test('rankings stay with their own manga', () async {
    await seedFavorite(1);
    await seedFavorite(2);
    await priorities.setForManga(1, const ['One']);
    await priorities.setForManga(2, const ['Two', 'Three']);

    final decoded = decodeBackup(encodeBackup(await creator().create()));
    final byUrl = {
      for (final m in decoded.backupManga) m.url: m.scanlatorPriority,
    };
    expect(byUrl['manga/1'], const ['One']);
    expect(byUrl['manga/2'], const ['Two', 'Three']);
  });
}
