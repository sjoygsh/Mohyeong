import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/track/trackers/kitsu.dart';
import 'package:mohyeong/domain/track/model/track.dart';
import 'package:mohyeong/domain/track/model/tracker.dart';

/// AniList and Kitsu both carry a start and a finish reading date, and both
/// were READ into [Track] and then never written by anything: no `update`
/// payload sent them and nothing ever set them. A reader who used only
/// Mohyeong got neither date on their profile.
///
/// Kotlin `BaseTracker.setRemoteLastChapterRead` stamps the finish date in the
/// same breath as it sets the completed status, and `AddTracks.await` takes the
/// start date from the earliest history entry when a tracker is bound.
Track _track({
  int total = 0,
  int status = TrackStatus.reading,
  int startDate = 0,
  int finishDate = 0,
}) =>
    Track(
      id: 1,
      mangaId: 1,
      trackerId: TrackerIds.aniList,
      remoteId: 1,
      libraryId: 1,
      title: 'T',
      lastChapterRead: 1,
      totalChapters: total,
      status: status,
      score: 0,
      remoteUrl: '',
      startDate: startDate,
      finishDate: finishDate,
      private: false,
    );

void main() {
  group('the finish date is stamped when the entry completes', () {
    final now = DateTime.utc(2026, 3, 14, 9, 30);

    test('reaching a known total sets it', () {
      final done = _track(total: 20).withProgress(20, now: now);
      expect(done.status, TrackStatus.completed);
      expect(done.finishDate, now.millisecondsSinceEpoch);
    });

    test('an entry that already has one keeps it', () {
      // Re-syncing or re-reading must not move a date the user already has.
      final done = _track(total: 20, finishDate: 111).withProgress(20, now: now);
      expect(done.finishDate, 111);
    });

    test('progress short of the total sets no date', () {
      expect(_track(total: 20).withProgress(19, now: now).finishDate, 0);
    });

    test('an unknown total never completes, so never stamps', () {
      final t = _track().withProgress(999, now: now);
      expect(t.status, TrackStatus.reading);
      expect(t.finishDate, 0);
    });

    test('an already-completed entry is left alone entirely', () {
      final t = _track(total: 20, status: TrackStatus.completed)
          .withProgress(25, now: now);
      expect(t.finishDate, 0, reason: 'the fork returns early here');
      expect(t.lastChapterRead, 25);
    });
  });

  group('Kitsu date format', () {
    test('unset is null, not an epoch date', () {
      // Sending 1970-01-01 would write a wrong date onto the account.
      expect(kitsuDate(0), isNull);
    });

    test('matches KitsuDateHelper\'s pattern exactly', () {
      final at = DateTime(2026, 3, 14, 9, 5, 7, 42);
      expect(kitsuDate(at.millisecondsSinceEpoch), '2026-03-14T09:05:07.042Z');
    });

    test('every component is zero-padded', () {
      final at = DateTime(2026, 1, 2, 3, 4, 5, 6);
      expect(kitsuDate(at.millisecondsSinceEpoch), '2026-01-02T03:04:05.006Z');
    });
  });
}
