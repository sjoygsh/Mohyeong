import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/manga/scanlator_priority_repository.dart';
import 'package:mohyeong/data/backup/backup_creator.dart';
import 'package:mohyeong/data/base/base_preferences.dart';
import 'package:mohyeong/data/category/category_repository.dart';
import 'package:mohyeong/data/chapter/chapter_repository.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/data/manga/excluded_scanlators_repository.dart';
import 'package:mohyeong/data/manga/manga_repository.dart';
import 'package:mohyeong/data/source/source_repository.dart';
import 'package:mohyeong/data/sync/sync_preferences.dart';
import 'package:mohyeong/data/track/track_repository.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sync device id and the last-sync high-water mark are THIS DEVICE's
/// state, not settings, and both used to ride along in every backup.
///
/// Restoring onto a second phone handed it the first phone's identity — the
/// one thing a device id exists to keep distinct — and the first phone's
/// last-sync stamp, so a phone that had never synced claimed to be up to date
/// and the server withheld everything older than that mark. Same class as the
/// `__APP_STATE_` storage keys already caught; these two were missed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  BackupCreator creatorFor() => BackupCreator(
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

  test('neither the device id nor the last-sync stamp reaches a backup',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SyncPreferences(prefs: await SharedPreferences.getInstance());
    await prefs.write(prefs.read().copyWith(
          host: 'https://sync.example',
          deviceId: 'device-A',
          lastSyncTimestamp: 1700000000000,
        ));

    final backup = await creatorFor().create();
    final keys = backup.backupPreferences.map((p) => p.key).toSet();

    expect(
      keys.any((k) => k.contains('sync_device_id')),
      isFalse,
      reason: 'phone B must never inherit phone A\'s sync identity',
    );
    expect(
      keys.any((k) => k.contains('sync_last_timestamp')),
      isFalse,
      reason: 'phone B must not claim phone A\'s sync high-water mark',
    );
    // The genuinely portable settings still travel.
    expect(keys, contains('pref_sync_host'));
  });

  test('an existing install keeps its id and stamp across the key move',
      () async {
    // What an install written by the previous version looks like on disk.
    SharedPreferences.setMockInitialValues({
      'pref_sync_device_id': 'legacy-device',
      'pref_sync_last_timestamp': 1690000000000,
    });
    final prefs = SyncPreferences(prefs: await SharedPreferences.getInstance());

    final read = prefs.read();
    expect(read.deviceId, 'legacy-device');
    expect(read.lastSyncTimestamp, 1690000000000);
  });

  test('writing drops the pre-prefix copies so they stop being exported',
      () async {
    SharedPreferences.setMockInitialValues({
      'pref_sync_device_id': 'legacy-device',
      'pref_sync_last_timestamp': 1690000000000,
    });
    final store = await SharedPreferences.getInstance();
    final prefs = SyncPreferences(prefs: store);

    await prefs.write(prefs.read());

    expect(store.getString('pref_sync_device_id'), isNull);
    expect(store.getInt('pref_sync_last_timestamp'), isNull);
    expect(
      store.getString('${appStatePrefix}pref_sync_device_id'),
      'legacy-device',
    );
    expect(
      store.getInt('${appStatePrefix}pref_sync_last_timestamp'),
      1690000000000,
    );

    // And a backup taken right after carries neither spelling.
    final backup = await creatorFor().create();
    expect(
      backup.backupPreferences.any((p) => p.key.contains('sync_device_id')),
      isFalse,
    );
  });

  test('setLastSyncTimestamp also clears the legacy copy', () async {
    SharedPreferences.setMockInitialValues({
      'pref_sync_last_timestamp': 1690000000000,
    });
    final store = await SharedPreferences.getInstance();
    final prefs = SyncPreferences(prefs: store);

    await prefs.setLastSyncTimestamp(1700000000000);

    expect(store.getInt('pref_sync_last_timestamp'), isNull);
    expect(prefs.read().lastSyncTimestamp, 1700000000000);
  });
}
