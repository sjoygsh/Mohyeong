import '../../chapter/model/chapter.dart';
import '../model/manga.dart';

/// Result of a fetch-interval recompute, ready to persist onto a manga row.
class MangaFetchUpdate {
  const MangaFetchUpdate({
    required this.nextUpdate,
    required this.fetchInterval,
    this.lastUpdate,
  });

  /// Epoch-ms timestamp of the next expected chapter release.
  final int nextUpdate;

  /// Recomputed update interval in days (or a preserved negative pin).
  final int fetchInterval;

  /// New `last_update` stamp, set only when new chapters were found this
  /// pass (null leaves the existing value untouched).
  final int? lastUpdate;
}

/// 1:1 port of Mihon's `tachiyomi.domain.manga.interactor.FetchInterval`.
///
/// Derives a per-manga update interval from its chapter upload/fetch history
/// and projects the next expected update time. Pure + synchronous — callers
/// supply the chapter list and "now", so it has no repository dependency.
class FetchInterval {
  const FetchInterval();

  static const int maxInterval = 28;
  static const int _gracePeriodDays = 1;

  /// Computes the interval + next-update for [manga]. [hasNewChapters] is
  /// true when the just-completed sync added rows — in which case the
  /// projection anchors on "now" and a fresh `last_update` is emitted.
  MangaFetchUpdate toMangaUpdate(
    Manga manga,
    List<Chapter> chapters,
    DateTime now, {
    required bool hasNewChapters,
  }) =>
      toMangaUpdateFromDates(
        manga,
        [for (final c in chapters) (c.dateUpload, c.dateFetch)],
        now,
        hasNewChapters: hasNewChapters,
      );

  /// [toMangaUpdate] over a date projection — see [calculateIntervalFromDates].
  MangaFetchUpdate toMangaUpdateFromDates(
    Manga manga,
    List<(int, int)> dates,
    DateTime now, {
    required bool hasNewChapters,
  }) {
    // A negative pinned interval means the user disabled auto-update; keep
    // it verbatim (Mihon `manga.fetchInterval.takeIf { it < 0 }`).
    final interval =
        manga.fetchInterval < 0 ? manga.fetchInterval : calculateIntervalFromDates(dates, now);
    final window = getWindow(now);
    final effectiveLastUpdate =
        hasNewChapters ? now.millisecondsSinceEpoch : manga.lastUpdate;
    final nextUpdate =
        _calculateNextUpdate(manga, interval, now, window, effectiveLastUpdate);
    return MangaFetchUpdate(
      nextUpdate: nextUpdate,
      fetchInterval: interval,
      lastUpdate: hasNewChapters ? now.millisecondsSinceEpoch : null,
    );
  }

  /// The "release period" grace window around today, in epoch-ms — an
  /// already-scheduled next-update landing inside it is left as-is.
  (int, int) getWindow(DateTime now) {
    final today = _epochDay(now.millisecondsSinceEpoch);
    final lower = _epochDayToMidnightMs(today - _gracePeriodDays);
    final upper = _epochDayToMidnightMs(today + _gracePeriodDays);
    return (lower, upper - 1);
  }

  /// Median consecutive-release delta over the most recent chapters,
  /// preferring source upload dates and falling back to client fetch
  /// dates, then to a 7-day default. Clamped to 1..[maxInterval].
  int calculateInterval(List<Chapter> chapters, DateTime now) =>
      calculateIntervalFromDates(
        [for (final c in chapters) (c.dateUpload, c.dateFetch)],
        now,
      );

  /// The same calculation over just the two columns it actually reads.
  ///
  /// Only ever needs a handful of distinct days, so callers that would have
  /// to deserialize a whole chapter list to get here — a 3,800-chapter series
  /// costs ~17ms in mapping alone — can hand over a projection instead.
  int calculateIntervalFromDates(List<(int, int)> dates, DateTime now) {
    final chapterWindow = dates.length <= 8 ? 3 : 10;

    final uploadDays = _distinctTake(
      dates
          .where((d) => d.$1 > 0)
          .map((d) => _epochDay(d.$1))
          .toList()
        ..sort((a, b) => b.compareTo(a)),
      chapterWindow,
    );
    final fetchDays = _distinctTake(
      dates.map((d) => _epochDay(d.$2)).toList()
        ..sort((a, b) => b.compareTo(a)),
      chapterWindow,
    );

    final int interval;
    if (uploadDays.length >= 3) {
      interval = _medianDelta(uploadDays);
    } else if (fetchDays.length >= 3) {
      interval = _medianDelta(fetchDays);
    } else {
      interval = 7;
    }
    return interval.clamp(1, maxInterval);
  }

  int _calculateNextUpdate(
    Manga manga,
    int interval,
    DateTime now,
    (int, int) window,
    int lastUpdate,
  ) {
    if (manga.nextUpdate >= window.$1 && manga.nextUpdate <= window.$2 + 1) {
      return manga.nextUpdate;
    }
    final latestEpochDay =
        _epochDay(lastUpdate > 0 ? lastUpdate : now.millisecondsSinceEpoch);
    final nowEpochDay = _epochDay(now.millisecondsSinceEpoch);
    final timeSinceLatest = (nowEpochDay - latestEpochDay).clamp(0, 1 << 31);
    final divisor = interval < 0
        ? interval.abs()
        : _increaseInterval(interval, timeSinceLatest, 10);
    final cycle = timeSinceLatest ~/ divisor;
    final nextEpochDay = latestEpochDay + (cycle + 1) * interval.abs();
    return _epochDayToMidnightMs(nextEpochDay);
  }

  int _increaseInterval(int delta, int timeSinceLatest, int increaseWhenOver) {
    if (delta >= maxInterval) return maxInterval;
    final cycle = timeSinceLatest ~/ delta + 1;
    if (cycle > increaseWhenOver) {
      return _increaseInterval(delta * 2, timeSinceLatest, increaseWhenOver);
    }
    return delta;
  }

  /// Median of consecutive deltas over [days] (sorted descending). Mirrors
  /// Kotlin `ranges[(ranges.size - 1) / 2]` after ascending sort.
  int _medianDelta(List<int> days) {
    final ranges = <int>[];
    for (var i = 0; i + 1 < days.length; i++) {
      ranges.add(days[i] - days[i + 1]);
    }
    ranges.sort();
    return ranges[(ranges.length - 1) ~/ 2];
  }

  /// Dedupe (preserving the already-sorted descending order) then take the
  /// first [n].
  List<int> _distinctTake(List<int> sortedDesc, int n) {
    final out = <int>[];
    for (final d in sortedDesc) {
      if (out.isEmpty || out.last != d) out.add(d);
      if (out.length == n) break;
    }
    return out;
  }

  /// Epoch-day index of [ms] in the device-local calendar (DST-safe: the
  /// local Y/M/D is re-anchored to UTC midnight before dividing).
  static int _epochDay(int ms) {
    final local = DateTime.fromMillisecondsSinceEpoch(ms);
    final utcMidnight = DateTime.utc(local.year, local.month, local.day);
    return utcMidnight.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  /// Inverse of [_epochDay]: local-midnight epoch-ms for a given epoch day.
  static int _epochDayToMidnightMs(int epochDay) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      epochDay * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day).millisecondsSinceEpoch;
  }
}
