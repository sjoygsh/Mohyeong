// ===========================================================================
// Tide upcoming.
//
// A calendar of predicted releases. The month grid is the screen's subject, so
// it sits on glass with the accent doing what the accent does: a lit ring
// marks today, and a lit dot under a date means something lands then. Tapping
// a marked day jumps the list beneath to it.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../tide/tide.dart';
import '../tide/tide_series_screen.dart';

/// Library manga whose next chapter is expected on/after today, soonest
/// first. Mirrors Mihon's `GetUpcomingManga`.
final upcomingMangaProvider = FutureProvider.autoDispose<List<Manga>>((ref) {
  return ref.read(mangaRepositoryProvider).getUpcoming();
});

/// Upcoming releases — a month calendar with per-day release dots over a
/// date-grouped list of library manga. Mihon parity (`UpcomingScreen`).
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  late DateTime _visibleMonth;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _scrollToDate(DateTime date) {
    final ctx = _headerKeys[date]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: tideEase,
        alignment: 0,
      );
    }
  }

  final Map<DateTime, GlobalKey> _headerKeys = {};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(upcomingMangaProvider);
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: 0.3)),
          Positioned.fill(
            child: TideRise(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TideHeader(
                    title: 'Upcoming',
                    actions: [
                      TideIconButton(
                        icon: Icons.help_outline,
                        onTap: () => launchUrl(
                          Uri.parse(
                            'https://sjoygsh.github.io/Mohyeong/help.html',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: async.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: TideColors.accent,
                        ),
                      ),
                      error: (e, _) => _Note('Failed to load: $e'),
                      data: _body,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Manga> manga) {
    // Count of releases per calendar day, for the calendar dots.
    final eventsByDay = <DateTime, int>{};
    for (final m in manga) {
      final d = _dateOnly(m.nextUpdate);
      eventsByDay[d] = (eventsByDay[d] ?? 0) + 1;
    }
    _headerKeys
      ..clear()
      ..addEntries(eventsByDay.keys.map((d) => MapEntry(d, GlobalKey())));

    // Flatten into headered rows (manga is already next_update-asc).
    final rows = <Widget>[];
    DateTime? lastHeader;
    for (final m in manga) {
      final d = _dateOnly(m.nextUpdate);
      if (lastHeader == null || d != lastHeader) {
        lastHeader = d;
        rows.add(
          _DateHeader(
            key: _headerKeys[d],
            date: d,
            mangaCount: eventsByDay[d] ?? 0,
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _UpcomingTile(manga: m),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _MonthCalendar(
          month: _visibleMonth,
          eventsByDay: eventsByDay,
          onPrev: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
          onDayTap: (d) {
            if (eventsByDay.containsKey(d)) _scrollToDate(d);
          },
        ),
        if (manga.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 34, 28, 0),
            child: Text(
              'No upcoming releases. Library entries get a predicted '
              'next-update date after a library update runs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.62,
                color: Color(0x8AE9E9ED),
              ),
            ),
          )
        else
          ...rows,
      ],
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.eventsByDay,
    required this.onPrev,
    required this.onNext,
    required this.onDayTap,
  });

  final DateTime month;
  final Map<DateTime, int> eventsByDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first leading blanks (DateTime.weekday: Mon=1..Sun=7).
    final leading = firstOfMonth.weekday - 1;

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      cells.add(
        _DayCell(
          day: day,
          count: eventsByDay[date] ?? 0,
          isToday: date == todayOnly,
          onTap: () => onDayTap(date),
        ),
      );
    }

    const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: TideGlass(
        radius: 22,
        tintTop: 0.085,
        tintBottom: 0.03,
        highlight: 0.15,
        border: 0.10,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        child: Column(
          children: [
            Row(
              children: [
                _MonthArrow(icon: Icons.chevron_left, onTap: onPrev),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center,
                    style: TideText.title(size: 15)
                        .copyWith(color: TideColors.textBright),
                  ),
                ),
                _MonthArrow(icon: Icons.chevron_right, onTap: onNext),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final l in weekdayLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        l,
                        style: TideText.kicker(size: 10)
                            .copyWith(letterSpacing: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

/// One date. Today wears a lit ring; a day with releases carries a lit dot and
/// brighter type, and is the only kind of cell that is tappable.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: has ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: TideColors.accent.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: TideColors.accent.withValues(alpha: 0.28),
                        blurRadius: 12,
                      ),
                    ],
                  )
                : null,
            child: Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w500,
                color: isToday
                    ? TideColors.accentLight
                    : has
                        ? TideColors.text
                        : TideColors.textAt(0.35),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 5,
            child: has
                ? Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TideColors.accent,
                      boxShadow: [
                        BoxShadow(
                          color: TideColors.accent.withValues(alpha: 0.7),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 34,
        child: Icon(icon, size: 20, color: TideColors.textAt(0.55)),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({super.key, required this.date, required this.mangaCount});

  final DateTime date;
  final int mangaCount;

  // Mirrors Kotlin relativeDateText: Today/Tomorrow/Yesterday collapse to
  // a word, everything else falls back to an absolute date.
  String _relativeText() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = date.difference(today).inDays;
    switch (diff) {
      case 0:
        return 'Today';
      case 1:
        return 'Tomorrow';
      case -1:
        return 'Yesterday';
      default:
        return DateFormat('EEEE, MMM d').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TideSectionHeader(
      label: _relativeText(),
      trailing: mangaCount == 1 ? '1 entry' : '$mangaCount entries',
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: 16,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TideSeriesScreen(mangaId: manga.id),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 58,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: TideCover(manga: manga, cacheWidth: 240),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(),
                ),
                if ((manga.author ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    manga.author!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
}
