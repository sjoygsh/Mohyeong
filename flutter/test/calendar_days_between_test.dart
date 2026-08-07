// Pins the day-counting rule behind every "Today / Yesterday / <weekday>"
// label (History, Tide's Tonight feed, Upcoming).
//
// The bug this guards: those labels used to subtract two local midnights and
// read `Duration.inDays`. A Duration measures ABSOLUTE elapsed time, so on the
// day after a spring-forward the two midnights are 23 hours apart and the
// truncating division answers 0 — yesterday's reading filed under "Today".
// Reproduced out-of-band under `TZ=America/New_York` (this machine has no DST,
// so the case cannot be staged inside `flutter test`): for 2026-03-08 →
// 2026-03-09 the old expression gave 0 where the calendar says 1, and for
// 2026-03-02 → 2026-03-09 it gave 6 where the calendar says 7 — which also
// dropped a week-old row out of the absolute-date branch and into a weekday
// name. `calendarDaysBetween` answered 1 and 7.
//
// What CAN be pinned everywhere is the contract the labels rely on: the count
// is a property of the two calendar dates alone.

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/presentation/util/timestamp_format.dart';

void main() {
  group('calendarDaysBetween', () {
    test('counts whole days forward', () {
      expect(
        calendarDaysBetween(DateTime(2026, 8, 1), DateTime(2026, 8, 8)),
        7,
      );
    });

    test('is zero for two times on the same date', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 8, 7, 0, 0),
          DateTime(2026, 8, 7, 23, 59, 59),
        ),
        0,
      );
    });

    test('ignores the time of day entirely', () {
      // 23:59 → 00:01 is two minutes of elapsed time but one calendar day.
      // The old `Duration.inDays` subtraction answered 0 here.
      expect(
        calendarDaysBetween(
          DateTime(2026, 8, 7, 23, 59),
          DateTime(2026, 8, 8, 0, 1),
        ),
        1,
      );
    });

    test('goes negative for a date in the future', () {
      // History and Tonight rely on this to keep a future timestamp out of the
      // "within the last week" weekday branch.
      expect(
        calendarDaysBetween(DateTime(2026, 8, 10), DateTime(2026, 8, 7)),
        -3,
      );
    });

    test('crosses months, years and a leap day', () {
      expect(
        calendarDaysBetween(DateTime(2026, 1, 31), DateTime(2026, 2, 1)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2025, 12, 31), DateTime(2026, 1, 1)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2028, 2, 28), DateTime(2028, 3, 1)),
        2, // 2028 is a leap year
      );
    });
  });
}
