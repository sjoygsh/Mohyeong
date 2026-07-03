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

/// Regression coverage for [BackupRestorer]'s merge semantics against a live
/// local library. The data-loss contracts under test:
///  * replaying a backup must never UN-favorite an existing entry, blank its
///    local notes, reset its custom-cover stamp, or move its add-date later;
///  * chapters from a backup that predates lastModifiedAt stamping (0) merge
///    progress (OR flags / max page) instead of overwriting local state;
///  * a backup chapter that is provably newer still wins outright.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BackupRestorer restorer;
  late MangaRepository mangas;
  late ChapterRepository chapters;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mangas = MangaRepository(db);
    chapters = ChapterRepository(db);
    restorer = BackupRestorer(
      database: db,
      mangaRepository: mangas,
      chapterRepository: chapters,
      categoryRepository: CategoryRepository(db),
      historyRepository: HistoryRepository(db),
      trackRepository: TrackRepository(db),
      sourceRepository: SourceRepository(db),
      excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Backup backupWith(BackupManga m) => Backup(backupManga: [m]);

  test('replaying an old backup keeps local favorite/notes/cover/add-date',
      () async {
    // Seed: restore once, then let the "user" favorite it, write notes, set a
    // custom cover stamp, and backdate the add-date.
    await restorer.restore(backupWith(
      BackupManga(source: 7, url: 'm/1', title: 'Seed', favorite: true),
    ));
    await db.customStatement(
      "UPDATE mangas SET favorite = 1, notes = 'my note', "
      'cover_last_modified = 42, date_added = 1000',
    );

    // The stale backup says: not favorite, no notes, added later.
    await restorer.restore(backupWith(
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'Seed',
        favorite: false,
        dateAdded: 5000,
      ),
    ));

    final m = await mangas.getByUrlAndSource('m/1', 7);
    expect(m, isNotNull);
    expect(m!.favorite, isTrue, reason: 'restore must never un-favorite');
    expect(m.notes, 'my note', reason: 'empty backup notes must not blank');
    expect(m.coverLastModified, 42, reason: 'custom-cover stamp preserved');
    expect(m.dateAdded, 1000, reason: 'earliest add-date wins');
  });

  test('timestampless backup chapters merge progress instead of overwriting',
      () async {
    await restorer.restore(backupWith(
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'Seed',
        chapters: [
          BackupChapter(url: 'c/1', name: 'Ch 1', read: true, lastPageRead: 17),
          BackupChapter(url: 'c/2', name: 'Ch 2', bookmark: true),
        ],
      ),
    ));

    // Old-format backup (lastModifiedAt == 0) claims both chapters pristine.
    await restorer.restore(backupWith(
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'Seed',
        chapters: [
          BackupChapter(url: 'c/1', name: 'Ch 1', read: false, lastPageRead: 3),
          BackupChapter(url: 'c/2', name: 'Ch 2', bookmark: false),
        ],
      ),
    ));

    final m = await mangas.getByUrlAndSource('m/1', 7);
    final byUrl = {for (final c in await chapters.getByMangaId(m!.id)) c.url: c};
    expect(byUrl['c/1']!.read, isTrue, reason: 'OR-merge keeps read');
    expect(byUrl['c/1']!.lastPageRead, 17, reason: 'max page kept');
    expect(byUrl['c/2']!.bookmark, isTrue, reason: 'OR-merge keeps bookmark');
    // No duplicate rows were created by the replay.
    expect(byUrl.length, 2);
  });

  test('restoring multiple tracked manga keeps every track row', () async {
    // Regression: tracks are built with sentinel id -1; writing that id
    // literally made every insert target the same `_id = -1` row, so the
    // second manga's track clobbered the first.
    await restorer.restore(Backup(backupManga: [
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'One',
        tracking: [BackupTracking(syncId: 1, mediaId: 100, title: 'One')],
      ),
      BackupManga(
        source: 7,
        url: 'm/2',
        title: 'Two',
        tracking: [BackupTracking(syncId: 1, mediaId: 200, title: 'Two')],
      ),
    ]));

    final tracks = TrackRepository(db);
    final all = await tracks.getAll();
    expect(all, hasLength(2), reason: 'one track row per tracked manga');
    expect({for (final t in all) t.remoteId}, {100, 200});
    expect({for (final t in all) t.id}.length, 2, reason: 'distinct real ids');
    expect(all.every((t) => t.id > 0), isTrue);

    // The migration service uses a DIFFERENT sentinel (id 0, not -1) when
    // copying tracks to a merge target — it must not collapse rows either.
    final zero = all.first.copyWith(id: 0, trackerId: 2, remoteId: 300);
    await tracks.upsert(zero);
    final after = await tracks.getAll();
    expect(after, hasLength(3), reason: 'id-0 sentinel must autoincrement');
    expect(after.every((t) => t.id > 0), isTrue);
  });

  test('a provably newer backup chapter overwrites local state', () async {
    await restorer.restore(backupWith(
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'Seed',
        chapters: [
          BackupChapter(
            url: 'c/1',
            name: 'Ch 1',
            read: true,
            lastPageRead: 17,
            lastModifiedAt: 100,
          ),
        ],
      ),
    ));

    await restorer.restore(backupWith(
      BackupManga(
        source: 7,
        url: 'm/1',
        title: 'Seed',
        chapters: [
          BackupChapter(
            url: 'c/1',
            name: 'Ch 1',
            read: false,
            lastPageRead: 0,
            lastModifiedAt: 200,
          ),
        ],
      ),
    ));

    final m = await mangas.getByUrlAndSource('m/1', 7);
    final list = await chapters.getByMangaId(m!.id);
    expect(list.single.read, isFalse,
        reason: 'newer backup state wins outright');
    expect(list.single.lastPageRead, 0);
  });
}
