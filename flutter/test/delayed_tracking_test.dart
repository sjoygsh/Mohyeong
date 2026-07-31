import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/base/base_preferences.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/track/delayed_tracking_scheduler.dart';
import 'package:mohyeong/data/track/delayed_tracking_store.dart';
import 'package:mohyeong/data/track/track_repository.dart';
import 'package:mohyeong/data/track/track_updater.dart';
import 'package:mohyeong/data/track/tracker.dart';
import 'package:mohyeong/data/track/tracker_registry.dart';
import 'package:mohyeong/domain/track/model/track.dart';
import 'package:mohyeong/domain/track/model/tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A failed tracker push used to be swallowed with a comment claiming the
/// next sync would pick up the diff — nothing did, so a failure on the last
/// chapter of a finished series left that tracker permanently behind. These
/// pin the queue that now carries it (Mihon's `DelayedTrackingStore` +
/// `DelayedTrackingUpdateJob`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = DelayedTrackingStore();
  const trackerId = 9;

  late AppDatabase db;
  late TrackRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrackRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedTrack({
    int mangaId = 1,
    double lastChapterRead = 10,
    int totalChapters = 0,
    int status = TrackStatus.reading,
  }) async {
    await db.customInsert(
      'INSERT INTO mangas(_id,source,url,title,status,favorite,initialized,'
      'viewer,chapter_flags,cover_last_modified,date_added) '
      'VALUES(?,1,?,?,0,1,0,0,0,0,0)',
      variables: [
        Variable(mangaId),
        Variable('/m$mangaId'),
        Variable('M$mangaId'),
      ],
    );
    await db.customInsert(
      'INSERT INTO manga_sync(_id,manga_id,sync_id,remote_id,title,'
      'last_chapter_read,total_chapters,status,score,remote_url,start_date,'
      'finish_date,private) VALUES(?,?,?,1,?,?,?,?,0,?,0,0,0)',
      variables: [
        Variable(mangaId),
        Variable(mangaId),
        Variable(trackerId),
        Variable('T$mangaId'),
        Variable(lastChapterRead),
        Variable(totalChapters),
        Variable(status),
        Variable('https://example.test/$mangaId'),
      ],
    );
  }

  group('DelayedTrackingStore', () {
    test('queue keys are app-state keys, so backups never carry them', () {
      // Track ids are local manga_sync row ids. Restoring another phone's
      // queue would push its progress onto whatever rows hold those ids
      // here — the same class of bug as the __APP_STATE_ storage grant.
      expect(DelayedTrackingStore.keyPrefix.startsWith(appStatePrefix), isTrue);
      expect(DelayedTrackingStore.attemptsKey.startsWith(appStatePrefix),
          isTrue);
    });

    test('add raises the queued progress but never lowers it', () async {
      await store.add(7, 12);
      expect((await store.getItems()).single.lastChapterRead, 12);

      await store.add(7, 20);
      expect((await store.getItems()).single.lastChapterRead, 20);

      // A later failure at an earlier chapter must not walk it backwards.
      await store.add(7, 15);
      expect((await store.getItems()).single.lastChapterRead, 20);
    });

    test('remove drops only its own entry', () async {
      await store.add(1, 3);
      await store.add(2, 4);
      await store.remove(1);
      final items = await store.getItems();
      expect(items.map((i) => i.trackId), [2]);
    });
  });

  group('Track.withProgress', () {
    Track base({int total = 0, int status = TrackStatus.reading}) => Track(
          id: 1,
          mangaId: 1,
          trackerId: trackerId,
          remoteId: 1,
          libraryId: null,
          title: 'T',
          lastChapterRead: 1,
          totalChapters: total,
          status: status,
          score: 0,
          remoteUrl: '',
          startDate: 0,
          finishDate: 0,
          private: false,
        );

    test('reaching a known total completes the entry', () {
      expect(base(total: 20).withProgress(20).status, TrackStatus.completed);
    });

    test('an unknown total never completes', () {
      expect(base().withProgress(999).status, TrackStatus.reading);
    });

    test('starting a plan-to-read entry moves it to reading', () {
      final t = base(status: TrackStatus.planToRead).withProgress(2);
      expect(t.status, TrackStatus.reading);
      expect(t.lastChapterRead, 2);
    });
  });

  group('TrackUpdater', () {
    late _FakeTracker tracker;
    late _RecordingScheduler scheduler;
    late ProviderContainer container;
    late TrackUpdater updater;

    setUp(() {
      tracker = _FakeTracker();
      scheduler = _RecordingScheduler();
      final probe = Provider<TrackUpdater>(
        (ref) => TrackUpdater(ref, repo, TrackerRegistry([tracker])),
      );
      container = ProviderContainer(overrides: [
        delayedTrackingSchedulerProvider.overrideWithValue(scheduler),
      ]);
      addTearDown(container.dispose);
      updater = container.read(probe);
    });

    test('a failed push is queued and schedules the retry job', () async {
      await seedTrack(lastChapterRead: 10);
      tracker.failing = true;

      await updater.setLastChapterRead(mangaId: 1, chapterNumber: 11);

      final items = await store.getItems();
      expect(items.single.lastChapterRead, 11);
      expect(scheduler.calls, 1);
      // The local row must NOT claim progress the remote never accepted.
      final tracks = await repo.getByMangaId(1);
      expect(tracks.single.lastChapterRead, 10);
    });

    test('a push that lands clears an older queued attempt', () async {
      await seedTrack(lastChapterRead: 10);
      tracker.failing = true;
      await updater.setLastChapterRead(mangaId: 1, chapterNumber: 11);
      expect(await store.getItems(), isNotEmpty);

      tracker.failing = false;
      await updater.setLastChapterRead(mangaId: 1, chapterNumber: 12);

      expect(await store.getItems(), isEmpty);
      final tracks = await repo.getByMangaId(1);
      expect(tracks.single.lastChapterRead, 12);
    });

    test('a successful push never schedules the job', () async {
      await seedTrack(lastChapterRead: 10);

      await updater.setLastChapterRead(mangaId: 1, chapterNumber: 11);

      expect(scheduler.calls, 0);
      expect(await store.getItems(), isEmpty);
    });

    test('one enqueue covers a manga however many trackers failed', () async {
      await seedTrack(mangaId: 1, lastChapterRead: 10);
      // Second bound tracker on the same manga, also failing.
      final second = _FakeTracker(id: 10)..failing = true;
      await db.customInsert(
        'INSERT INTO manga_sync(_id,manga_id,sync_id,remote_id,title,'
        'last_chapter_read,total_chapters,status,score,remote_url,start_date,'
        'finish_date,private) VALUES(99,1,10,1,?,10,0,?,0,?,0,0,0)',
        variables: [
          Variable('T2'),
          Variable(TrackStatus.reading),
          Variable('https://example.test/2'),
        ],
      );
      tracker.failing = true;
      final probe = Provider<TrackUpdater>(
        (ref) => TrackUpdater(ref, repo, TrackerRegistry([tracker, second])),
      );
      final two = container.read(probe);

      await two.setLastChapterRead(mangaId: 1, chapterNumber: 11);

      expect((await store.getItems()).length, 2);
      expect(scheduler.calls, 1);
    });
  });

  group('drainDelayedTracking', () {
    // The retry job's whole point is what happens when a push fails, which is
    // also the hardest thing to stage by hand — it needs a real tracker
    // account and a broken network at the right moment. Driving the drain
    // directly is what makes it verifiable at all.
    late _FakeTracker tracker;

    setUp(() => tracker = _FakeTracker());

    Future<bool> drain({int maxAttempts = 3}) => drainDelayedTracking(
          store: store,
          getTrack: repo.getById,
          trackerFor: (id) => id == tracker.id ? tracker : null,
          upsert: repo.upsert,
          maxAttempts: maxAttempts,
        );

    test('a queued push that now lands clears the entry and saves it',
        () async {
      await seedTrack(lastChapterRead: 10);
      await store.add(1, 11);

      expect(await drain(), isTrue);

      expect(tracker.pushed, [11]);
      expect(await store.getItems(), isEmpty);
      expect((await repo.getByMangaId(1)).single.lastChapterRead, 11);
    });

    test('still unreachable keeps the entry and reports not-done', () async {
      await seedTrack(lastChapterRead: 10);
      await store.add(1, 11);
      tracker.failing = true;

      expect(await drain(), isFalse);

      expect((await store.getItems()).single.lastChapterRead, 11);
      // The local row must not claim progress the remote never accepted.
      expect((await repo.getByMangaId(1)).single.lastChapterRead, 10);
    });

    test('a logged-out tracker keeps the entry rather than dropping it',
        () async {
      await seedTrack(lastChapterRead: 10);
      await store.add(1, 11);
      tracker.loggedIn = false;

      expect(await drain(), isFalse);
      expect(await store.getItems(), isNotEmpty);
      expect(tracker.pushed, isEmpty);
    });

    test('a deleted track row drops its entry', () async {
      // Nothing seeded: the manga was removed while the push was queued.
      await store.add(404, 11);

      expect(await drain(), isTrue);
      expect(await store.getItems(), isEmpty);
    });

    test('a remote already ahead drops the entry without pushing', () async {
      await seedTrack(lastChapterRead: 20);
      await store.add(1, 11);

      expect(await drain(), isTrue);
      expect(tracker.pushed, isEmpty);
      expect(await store.getItems(), isEmpty);
    });

    test('one throwing entry cannot strand the rest of the queue', () async {
      // Reading the row crosses a method channel from the background isolate,
      // so it is a realistic thrower — and it used to sit OUTSIDE the
      // per-item try, where one throw abandoned every entry behind it. The
      // healthy entry must still go through in the same run.
      await seedTrack(mangaId: 1, lastChapterRead: 10);
      await seedTrack(mangaId: 2, lastChapterRead: 10);
      await store.add(1, 11);
      await store.add(2, 11);

      final done = await drainDelayedTracking(
        store: store,
        getTrack: (id) async {
          if (id == 1) throw TrackerException('credential channel died');
          return repo.getById(id);
        },
        trackerFor: (id) => id == tracker.id ? tracker : null,
        upsert: repo.upsert,
      );

      expect(done, isFalse);
      expect(tracker.pushed, [11], reason: 'entry 2 still pushed');
      expect((await store.getItems()).single.trackId, 1,
          reason: 'only the thrower stays queued');
    });

    test('the attempt cap stops retrying but keeps the entries', () async {
      await seedTrack(lastChapterRead: 10);
      await store.add(1, 11);
      await store.writeAttempts(3);

      // True so workmanager stops rescheduling; the entry survives for the
      // next real failure to pick up.
      expect(await drain(), isTrue);
      expect(tracker.pushed, isEmpty);
      expect(await store.getItems(), isNotEmpty);
    });

    test('an empty queue is done immediately', () async {
      expect(await drain(), isTrue);
    });
  });
}

class _FakeTracker extends Tracker {
  _FakeTracker({int id = 9}) : super(id, 'Fake', TrackerCategory.online);

  bool failing = false;
  bool loggedIn = true;
  final List<double> pushed = [];

  @override
  Future<bool> get isLoggedIn async => loggedIn;

  @override
  Future<void> login() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<List<TrackSearchResult>> search(String query) async => const [];

  @override
  Future<Track> refresh(Track track) async => track;

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    if (failing) throw TrackerException('offline');
    pushed.add(track.lastChapterRead);
    return track;
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async =>
      throw UnimplementedError();
}

class _RecordingScheduler extends DelayedTrackingScheduler {
  _RecordingScheduler();

  int calls = 0;

  @override
  Future<void> setupTask() async => calls++;
}
