import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/cover/cover_cache.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

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
    final key = _headerKeys[date];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0,
      );
    }
  }

  final Map<DateTime, GlobalKey> _headerKeys = {};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(upcomingMangaProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Upcoming Guide',
            onPressed: () => launchUrl(
              Uri.parse('https://sjoygsh.github.io/Mohyeong/help.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (manga) {
          if (manga.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No upcoming releases.\nLibrary manga get a predicted next-update '
                  'date after a library update.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Count of releases per calendar day, for the calendar dots.
          final eventsByDay = <DateTime, int>{};
          for (final m in manga) {
            final d = _dateOnly(m.nextUpdate);
            eventsByDay[d] = (eventsByDay[d] ?? 0) + 1;
          }
          _headerKeys
            ..clear()
            ..addEntries(
              eventsByDay.keys.map((d) => MapEntry(d, GlobalKey())),
            );

          // Flatten into headered rows (manga is already next_update-asc).
          final rows = <Widget>[];
          DateTime? lastHeader;
          for (final m in manga) {
            final d = _dateOnly(m.nextUpdate);
            if (lastHeader == null || d != lastHeader) {
              lastHeader = d;
              rows.add(_DateHeader(
                key: _headerKeys[d],
                date: d,
                mangaCount: eventsByDay[d] ?? 0,
              ));
            }
            rows.add(_UpcomingTile(manga: m));
          }

          return ListView(
            controller: _scroll,
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
              const Divider(height: 1),
              ...rows,
            ],
          );
        },
      ),
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
    final scheme = Theme.of(context).colorScheme;
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
      final count = eventsByDay[date] ?? 0;
      final isToday = date == todayOnly;
      cells.add(
        InkWell(
          onTap: count > 0 ? () => onDayTap(date) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        )
                      : null,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isToday ? scheme.onPrimary : scheme.onSurface,
                      fontWeight:
                          count > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: count > 0 ? scheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: onPrev,
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onNext,
              ),
            ],
          ),
          Row(
            children: [
              for (final l in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.74,
            children: cells,
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({
    super.key,
    required this.date,
    required this.mangaCount,
  });

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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            _relativeText(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$mangaCount',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingTile extends ConsumerWidget {
  const _UpcomingTile({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Container(
      width: 40,
      height: 56,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book, size: 20),
    );
    final url =
        ref.watch(coverCacheProvider).coverUrlFor(manga.id, manga.thumbnailUrl);
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: url == null || url.isEmpty
              ? fallback
              : SourceImage(
                  url: url,
                  fit: BoxFit.cover,
                  placeholder: (_) => fallback,
                  errorWidget: (_, _) => fallback,
                ),
        ),
      ),
      title: Text(manga.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(mangaId: manga.id),
        ),
      ),
    );
  }
}
