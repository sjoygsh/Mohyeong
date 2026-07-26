import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/cover/cover_cache.dart';
import 'package:mohyeong/data/history/history_repository.dart';
import 'package:mohyeong/presentation/history/history_screen.dart';

/// History's timeline collapses a run of chapters read in one sitting down to
/// a single titled card, and heads each day with what that day cost. Both are
/// derived, both are invisible to the shell test (which runs against an empty
/// repository), and both fail quietly — a broken run test just looks like a
/// slightly longer list. This renders the populated screen so they don't.

class _FakeCoverCache implements CoverCache {
  @override
  String? coverUrlFor(int mangaId, String? thumbnailUrl) => thumbnailUrl;

  @override
  bool hasCustomCover(int mangaId) => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryRepository implements HistoryRepository {
  _FakeHistoryRepository(this.entries, this.totalMs);

  final List<HistoryWithContext> entries;
  final int totalMs;

  /// Recorded so the delete path can be asserted without a database.
  final List<int> removedIds = [];
  final List<int> resetMangaIds = [];

  @override
  Stream<List<HistoryWithContext>> watchRecent({int limit = 200}) =>
      Stream.value(entries);

  @override
  Future<int> totalReadDurationMs() async => totalMs;

  @override
  Future<void> removeById(int historyId) async => removedIds.add(historyId);

  @override
  Future<void> resetByMangaId(int mangaId) async =>
      resetMangaIds.add(mangaId);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _minute = 60000;

HistoryWithContext _entry({
  required int id,
  required int mangaId,
  required String mangaTitle,
  required String chapterName,
  required double chapterNumber,
  required DateTime readAt,
  required int minutes,
}) =>
    HistoryWithContext(
      historyId: id,
      chapterId: id * 10,
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterName: chapterName,
      chapterNumber: chapterNumber,
      readAt: readAt,
      timeReadMs: minutes * _minute,
      source: 1,
      // No artwork: the cover falls back to Tide's deterministic gradient,
      // which is the path a test can actually exercise (no network).
      thumbnailUrl: null,
    );

Future<void> _pump(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  // Anchored to midnight rather than to `now` so the day buckets are the same
  // whatever time of day the suite runs at.
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);

  /// A sitting of three chapters of one series, then one chapter of another,
  /// then a single chapter the day before. Newest first, as the stream emits.
  List<HistoryWithContext> buildEntries() => [
        _entry(
          id: 1,
          mangaId: 1,
          mangaTitle: 'Omniscient Reader',
          chapterName: 'Chapter 158',
          chapterNumber: 158,
          readAt: midnight.add(const Duration(minutes: 4)),
          minutes: 12,
        ),
        _entry(
          id: 2,
          mangaId: 1,
          mangaTitle: 'Omniscient Reader',
          chapterName: 'Chapter 157',
          chapterNumber: 157,
          readAt: midnight.add(const Duration(minutes: 3)),
          minutes: 20,
        ),
        _entry(
          id: 3,
          mangaId: 1,
          mangaTitle: 'Omniscient Reader',
          chapterName: 'Chapter 156',
          chapterNumber: 156,
          readAt: midnight.add(const Duration(minutes: 2)),
          minutes: 18,
        ),
        _entry(
          id: 4,
          mangaId: 2,
          mangaTitle: 'Ending Maker',
          chapterName: 'Chapter 42',
          chapterNumber: 42,
          readAt: midnight.add(const Duration(minutes: 1)),
          minutes: 10,
        ),
        _entry(
          id: 5,
          mangaId: 1,
          mangaTitle: 'Omniscient Reader',
          chapterName: 'Chapter 155',
          chapterNumber: 155,
          readAt: midnight.subtract(const Duration(hours: 2)),
          minutes: 25,
        ),
      ];

  Future<_FakeHistoryRepository> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // 85 minutes across the five entries.
    final repo = _FakeHistoryRepository(buildEntries(), 85 * _minute);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyRepositoryProvider.overrideWithValue(repo),
          coverCacheProvider.overrideWithValue(_FakeCoverCache()),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await _pump(tester);
    return repo;
  }

  testWidgets('a sitting collapses to one titled card per series per day',
      (WidgetTester tester) async {
    await pumpScreen(tester);

    // Three consecutive chapters of one series are ONE card, not three: the
    // title appears once for today's run and once again for yesterday's.
    expect(find.text('Omniscient Reader'), findsNWidgets(2));
    expect(find.text('Ending Maker'), findsOneWidget);

    // The run's leader carries its chapter in the card's caption (with the
    // read stamp appended), and the rest hang off the spine as bare lines.
    expect(find.textContaining('Chapter 158'), findsOneWidget);
    expect(find.text('Chapter 157'), findsOneWidget);
    expect(find.text('Chapter 156'), findsOneWidget);
  });

  testWidgets('each day is headed with its chapters and time',
      (WidgetTester tester) async {
    await pumpScreen(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    // 12 + 20 + 18 + 10 minutes over four chapters, then 25 over one.
    expect(find.text('4 chapters · 1h'), findsOneWidget);
    expect(find.text('1 chapter · 25m'), findsOneWidget);

    // The all-time figure the database always held and nothing ever showed.
    expect(find.text('TOTAL TIME READ'), findsOneWidget);
    expect(find.text('1h 25m'), findsOneWidget);
  });

  testWidgets('search filters by series and empties out cleanly',
      (WidgetTester tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.search));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'ending');
    await _pump(tester);

    expect(find.text('Ending Maker'), findsOneWidget);
    expect(find.text('Omniscient Reader'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await _pump(tester);
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('the remove sheet deletes one entry, or resets the series',
      (WidgetTester tester) async {
    final repo = await pumpScreen(tester);

    // The first row's remove control — the newest entry, history id 1.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await _pump(tester);
    expect(find.text('Reset all chapters for this entry'), findsOneWidget);

    await tester.tap(find.text('Remove').last);
    await _pump(tester);
    expect(repo.removedIds, [1]);
    expect(repo.resetMangaIds, isEmpty);

    // Same control, with the reset toggle on: the whole series is reset
    // instead of the single row.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await _pump(tester);
    await tester.tap(find.text('Reset all chapters for this entry'));
    await _pump(tester);
    await tester.tap(find.text('Remove').last);
    await _pump(tester);
    expect(repo.removedIds, [1]);
    expect(repo.resetMangaIds, [1]);
  });
}
