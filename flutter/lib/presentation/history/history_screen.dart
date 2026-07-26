// ===========================================================================
// Tide history.
//
// A history list is not a shelf, and the old flat run of identical tiles hid
// the one thing the data actually has: shape. Reading is bursty — you read six
// chapters of one series in one sitting, then nothing for two days — so the
// screen is built as a timeline rather than a list.
//
//   spine     one lit thread down the left; it breaks between days, so a gap
//             in reading is visible as a gap
//   runs      the first chapter of a sitting carries the cover and the series
//             name; the rest of that sitting hang off the same thread as bare
//             chapter lines, because repeating the cover six times says
//             nothing the first one didn't
//   day       each day is headed with what it cost: chapters, and time
//
// Time read is stored per chapter and was never shown anywhere; the strip
// under the header is the app's "total time read" stat, finally on screen.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cover/cover_cache.dart';
import '../../data/history/history_repository.dart';
import '../../data/preferences/appearance_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../common/source_image.dart';
import '../home/home_screen.dart';
import '../reader/reader_screen.dart';
import '../tide/tide.dart';
import '../tide/tide_series_screen.dart';
import '../util/timestamp_format.dart';

/// The feed this screen renders: the recent-history join, paired with the
/// all-time read duration.
///
/// The two travel together rather than as a stream plus a one-shot future
/// because every event that changes the total — finishing a chapter, deleting
/// a row — also emits on the history stream. Re-querying alongside it keeps
/// the headline figure from going stale while the tab sits alive in the
/// shell's IndexedStack.
typedef _Feed = (List<HistoryWithContext> entries, int totalReadMs);

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _searching = false;
  String _query = '';

  /// Created once — building it in `build` re-ran the recent-history join
  /// on every search keystroke (each setState resubscribed the stream).
  late final Stream<_Feed> _feed = () {
    final repo = ref.read(historyRepositoryProvider);
    return repo
        .watchRecent()
        .asyncMap((entries) async => (entries, await repo.totalReadDurationMs()));
  }();

  /// Memoised filter + grouping output. Recomputed only when the stream emits
  /// a new list, the query changes, or the calendar day rolls over (the key
  /// carries today's date so "Today"/"Yesterday" labels stay correct across
  /// midnight) — not on every rebuild.
  Object? _rowsKey;
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    // Reselecting the tab returns to the top, matching the other tabs.
    ref.listenManual<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab != 1 || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: tideEase,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The shell keeps every tab alive in an IndexedStack, so without this the
    // aurora would go on animating — and drawing — while the reader is on
    // another tab entirely. Same guard Tide's home uses.
    final visible = ref.watch(homeTabIndexProvider) == 1;
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: TickerMode(
        enabled: visible,
        child: Scaffold(
          backgroundColor: TideColors.ground,
          body: Stack(
            children: [
              // Dimmer than the home feed's: this screen is a record, and the
              // light behind it should stay behind it.
              const Positioned.fill(child: TideAurora(opacity: 0.3)),
              Positioned.fill(
                child: StreamBuilder<_Feed>(
                  stream: _feed,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _Message('Error: ${snap.error}');
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: TideColors.accent,
                        ),
                      );
                    }
                    final (entries, totalReadMs) = snap.data!;
                    return _content(entries, totalReadMs);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(List<HistoryWithContext> entries, int totalReadMs) {
    // Substring match on manga title — same lightweight case-insensitive
    // contains the Library search uses. Grouping runs after filtering so the
    // day headers only count the visible rows.
    final q = _query.toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rowsKey = (entries, q, today);
    if (rowsKey != _rowsKey) {
      final filtered = q.isEmpty
          ? entries
          : entries
              .where((e) => e.mangaTitle.toLowerCase().contains(q))
              .toList(growable: false);
      _rows = _buildRows(filtered, today);
      _rowsKey = rowsKey;
    }
    final rows = _rows;
    final relative = ref.watch(relativeTimestampsProvider);
    final pattern = ref.watch(dateFormatProvider);

    return TideRise(
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: _header()),
          // The strip is the total across all of history, not just the rows
          // loaded here, so it stays out of the way of a search: filtering the
          // list doesn't change how long you have been reading.
          if (totalReadMs >= 60000 && entries.isNotEmpty)
            SliverToBoxAdapter(child: _TotalStrip(totalReadMs: totalReadMs)),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 80),
                child: entries.isEmpty
                    ? const _EmptyCard(
                        title: 'Nothing read recently',
                        message: 'Chapters you read show up here, newest '
                            'first — with where each sitting started and how '
                            'long it ran.',
                      )
                    : const _EmptyCard(
                        title: 'No results found',
                        message: 'No series in your history matches that.',
                      ),
              ),
            )
          else
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => switch (rows[i]) {
                final _DayRow row => _DayHeader(day: row.day),
                final _EntryRow row => _EntryTile(
                    row: row,
                    relative: relative,
                    pattern: pattern,
                    onOpenChapter: _openChapter,
                    onOpenSeries: _openSeries,
                    onRemove: _confirmRemove,
                  ),
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  /// Greeting-height title and the two round controls, in the shape Tide's
  /// home header established. In search mode the whole row becomes the field —
  /// there is no app bar to hang a text box off any more.
  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        14,
      ),
      child: _searching
          ? Row(
              children: [
                TideIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 15,
                  onTap: _closeSearch,
                ),
                const SizedBox(width: 10),
                Expanded(child: _SearchField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  onClear: _query.isEmpty
                      ? null
                      : () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                )),
              ],
            )
          : Row(
              children: [
                const Expanded(
                  child: Text(
                    'History',
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.65,
                      color: TideColors.text,
                    ),
                  ),
                ),
                TideIconButton(icon: Icons.search, onTap: _openSearch),
                const SizedBox(width: 9),
                TideIconButton(
                  icon: Icons.delete_sweep_outlined,
                  onTap: _confirmClearAll,
                ),
              ],
            ),
    );
  }

  Future<void> _openChapter(HistoryWithContext entry) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            mangaId: entry.mangaId,
            chapterId: entry.chapterId,
          ),
        ),
      );

  Future<void> _openSeries(HistoryWithContext entry) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TideSeriesScreen(mangaId: entry.mangaId),
        ),
      );

  Future<void> _confirmClearAll() async {
    final repo = ref.read(historyRepositoryProvider);
    final confirmed = await showTideSheet<bool>(
      context,
      (ctx) => TideConfirmSheet(
        title: 'Remove everything',
        message: 'Are you sure? All history will be lost.',
        confirmLabel: 'Remove',
      ),
    );
    if (confirmed == true) await repo.removeAll();
  }

  /// Per-entry delete. Mirrors Kotlin `HistoryDeleteDialog`: removes this
  /// entry's read date, or — when the toggle is on — resets every chapter's
  /// history for this series.
  Future<void> _confirmRemove(HistoryWithContext entry) async {
    final repo = ref.read(historyRepositoryProvider);
    var removeEverything = false;
    final confirmed = await showTideSheet<bool>(
      context,
      (ctx) => TideConfirmSheet(
        title: 'Remove',
        message: 'This will remove the read date of this chapter. '
            'Are you sure?',
        confirmLabel: 'Remove',
        extra: (setSheetState) => TideCheck(
          label: 'Reset all chapters for this entry',
          value: removeEverything,
          onChanged: (v) => setSheetState(() => removeEverything = v),
        ),
      ),
    );
    if (confirmed != true) return;
    if (removeEverything) {
      await repo.resetByMangaId(entry.mangaId);
    } else {
      await repo.removeById(entry.historyId);
    }
  }
}

// ---------------------------------------------------------------------------
// Row model
// ---------------------------------------------------------------------------

sealed class _Row {
  const _Row();
}

class _DayRow extends _Row {
  const _DayRow(this.day);
  final _Day day;
}

class _EntryRow extends _Row {
  const _EntryRow(
    this.entry, {
    required this.lead,
    required this.lineAbove,
    required this.lineBelow,
  });

  final HistoryWithContext entry;

  /// First chapter of a run on this series within this day — the row that
  /// carries the cover and the title.
  final bool lead;

  /// Whether the spine continues past this row. False at the two ends of a
  /// day, which is what makes a break in reading legible.
  final bool lineAbove;
  final bool lineBelow;
}

/// One calendar day's worth of entries, with the totals its header shows.
class _Day {
  _Day(this.label);

  final String label;
  final List<HistoryWithContext> entries = [];

  int get chapters => entries.length;
  int get timeReadMs =>
      entries.fold(0, (sum, e) => sum + e.timeReadMs);
}

/// Walks the entries in stream-order (most recent first), buckets them by day,
/// and flattens the result into the rows the list builds. Entries with
/// `readAt == null` bucket under "Unknown". [today] is the midnight-truncated
/// current date, resolved once by the caller rather than per entry.
List<_Row> _buildRows(List<HistoryWithContext> entries, DateTime today) {
  final days = <_Day>[];
  for (final e in entries) {
    final label = _dayLabel(e.readAt, today);
    if (days.isEmpty || days.last.label != label) days.add(_Day(label));
    days.last.entries.add(e);
  }

  final rows = <_Row>[];
  for (final day in days) {
    rows.add(_DayRow(day));
    int? lastMangaId;
    for (final (i, e) in day.entries.indexed) {
      rows.add(_EntryRow(
        e,
        lead: e.mangaId != lastMangaId,
        lineAbove: i > 0,
        lineBelow: i < day.entries.length - 1,
      ));
      lastMangaId = e.mangaId;
    }
  }
  return rows;
}

String _dayLabel(DateTime? t, DateTime today) {
  if (t == null) return 'Unknown';
  final that = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(that).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Yesterday';
  if (diffDays < 7) return _weekdayName(that.weekday);
  return '${that.year}-${that.month.toString().padLeft(2, '0')}-${that.day.toString().padLeft(2, '0')}';
}

String _weekdayName(int weekday) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[(weekday - 1) % 7];
}

/// Coarse duration in the design's voice: "18m", "1h 12m". Anything under a
/// minute reads as nothing at all rather than as "0m".
String _durationLabel(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 1) return '';
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

/// Formats a chapter number the way Kotlin's `formatChapterNumber` does:
/// drop a trailing ".0" for whole numbers, otherwise keep the decimals.
String _formatChapterNumber(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
}

/// Chapter label for a row: the source's own name when it has one, else
/// "Ch. 12" from the number.
String _chapterLabel(HistoryWithContext e) {
  final name = e.chapterName.trim();
  if (name.isNotEmpty) return name;
  if (e.chapterNumber <= -1) return 'Chapter';
  return 'Ch. ${_formatChapterNumber(e.chapterNumber)}';
}

/// The read stamp, honouring the appearance preferences: Tide's compact voice
/// when relative timestamps are on, the user's own date pattern when off.
String _stamp(DateTime? t, {required bool relative, required String pattern}) {
  if (t == null) return '';
  return relative
      ? tideRelative(t)
      : formatTimestamp(t, relative: false, pattern: pattern);
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

/// The one figure the app kept in the database and never showed.
class _TotalStrip extends StatelessWidget {
  const _TotalStrip({required this.totalReadMs});

  final int totalReadMs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: TideGlass(
        radius: 18,
        tintTop: 0.075,
        tintBottom: 0.026,
        highlight: 0.14,
        border: 0.09,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'TOTAL TIME READ',
                style: TideText.kicker(size: 10.5).copyWith(
                  letterSpacing: 1.7,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _durationLabel(totalReadMs),
              style: const TextStyle(
                fontSize: 18,
                height: 1.1,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.36,
                color: TideColors.textBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final _Day day;

  @override
  Widget build(BuildContext context) {
    final time = _durationLabel(day.timeReadMs);
    final chapters =
        day.chapters == 1 ? '1 chapter' : '${day.chapters} chapters';
    return TideSectionHeader(
      label: day.label,
      trailing: time.isEmpty ? chapters : '$chapters · $time',
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
    );
  }
}

/// One row hung off the spine. A lead row is a glass card with the cover and
/// the series; the rest of a sitting are bare chapter lines.
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.row,
    required this.relative,
    required this.pattern,
    required this.onOpenChapter,
    required this.onOpenSeries,
    required this.onRemove,
  });

  final _EntryRow row;
  final bool relative;
  final String pattern;
  final ValueChanged<HistoryWithContext> onOpenChapter;
  final ValueChanged<HistoryWithContext> onOpenSeries;
  final ValueChanged<HistoryWithContext> onRemove;

  /// Width of the spine gutter, and where the thread sits inside it.
  static const _gutter = 30.0;

  /// Card and line heights are fixed rather than intrinsic so the spine knows
  /// exactly where to put its node without a second layout pass.
  static const _leadHeight = 80.0;
  static const _followHeight = 34.0;

  @override
  Widget build(BuildContext context) {
    final lead = row.lead;
    final height = lead ? _leadHeight : _followHeight;
    final gap = lead ? 8.0 : 6.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          // Drawn across the row AND the gap below it, so the thread is
          // continuous down a day instead of dashed by the spacing.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _gutter,
            child: CustomPaint(
              painter: _SpinePainter(
                above: row.lineAbove,
                below: row.lineBelow,
                lead: lead,
                nodeY: height / 2,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: _gutter, bottom: gap),
            child: SizedBox(
              height: height,
              child: lead ? _leadCard(context) : _followLine(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadCard(BuildContext context) {
    final e = row.entry;
    final stamp = _stamp(e.readAt, relative: relative, pattern: pattern);
    return TideGlass(
      radius: 18,
      onTap: () => onOpenChapter(e),
      padding: const EdgeInsets.fromLTRB(11, 11, 6, 11),
      child: Row(
        children: [
          // Cover tap opens the series (Kotlin onClickCover); the rest of the
          // row resumes reading (Kotlin onClickResume).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenSeries(e),
            child: SizedBox(
              width: 44,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _HistoryCover(entry: e),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.mangaTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(),
                ),
                const SizedBox(height: 2),
                Text(
                  stamp.isEmpty
                      ? _chapterLabel(e)
                      : '${_chapterLabel(e)} · $stamp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.caption(),
                ),
              ],
            ),
          ),
          _QuietX(onTap: () => onRemove(e)),
        ],
      ),
    );
  }

  Widget _followLine(BuildContext context) {
    final e = row.entry;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenChapter(e),
      child: Padding(
        padding: const EdgeInsets.only(left: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _chapterLabel(e),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TideText.title(size: 13, color: TideColors.textAt(0.72)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _stamp(e.readAt, relative: relative, pattern: pattern),
              style: TideText.caption(size: 11, opacity: 0.32),
            ),
            _QuietX(onTap: () => onRemove(e), size: 30),
          ],
        ),
      ),
    );
  }
}

/// A small dismissing ✕ — removes a history row, or clears the search field.
///
/// Quiet, but present. History's delete is a real affordance in the Kotlin
/// app and hiding it behind a long-press would have been a downgrade dressed
/// up as restraint.
class _QuietX extends StatelessWidget {
  const _QuietX({required this.onTap, this.size = 34});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.close_rounded,
          size: 15,
          color: TideColors.textAt(0.26),
        ),
      ),
    );
  }
}

/// The thread, and this row's node on it.
class _SpinePainter extends CustomPainter {
  const _SpinePainter({
    required this.above,
    required this.below,
    required this.lead,
    required this.nodeY,
  });

  final bool above;
  final bool below;
  final bool lead;
  final double nodeY;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width - 12;
    final line = Paint()
      ..strokeWidth = 1
      ..color = TideColors.accent.withValues(alpha: 0.15);
    if (above) canvas.drawLine(Offset(x, 0), Offset(x, nodeY), line);
    if (below) canvas.drawLine(Offset(x, nodeY), Offset(x, size.height), line);

    // A halo ring rather than a blur: a MaskFilter on every visible row of a
    // long list is a real cost, and two flat circles read the same at 7px.
    if (lead) {
      canvas.drawCircle(
        Offset(x, nodeY),
        6.5,
        Paint()..color = TideColors.accent.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        Offset(x, nodeY),
        3.2,
        Paint()..color = TideColors.accent,
      );
    } else {
      canvas.drawCircle(
        Offset(x, nodeY),
        2.2,
        Paint()..color = TideColors.accent.withValues(alpha: 0.42),
      );
    }
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.above != above ||
      old.below != below ||
      old.lead != lead ||
      old.nodeY != nodeY;
}

/// A history row's cover, resolved through the same custom-cover cache and
/// per-source headers the rest of the app uses. Falls back to Tide's
/// deterministic gradient rather than a grey box with a glyph in it.
class _HistoryCover extends ConsumerWidget {
  const _HistoryCover({required this.entry});

  final HistoryWithContext entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: TideCover.fallbackGradient(entry.mangaId),
      ),
    );
    final url = ref
        .watch(coverCacheProvider)
        .coverUrlFor(entry.mangaId, entry.thumbnailUrl);
    if (url == null || url.isEmpty) return fallback;
    final headers = ref
        .watch(installedSourceImageHeadersProvider)
        .valueOrNull?[entry.source];
    return SourceImage(
      url: url,
      headers: headers,
      cacheWidth: 180,
      fit: BoxFit.cover,
      placeholder: (_) => fallback,
      errorWidget: (_, _) => fallback,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TideGlass(
        radius: 20,
        tintTop: 0.09,
        tintBottom: 0.03,
        highlight: 0.16,
        border: 0.11,
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                cursorColor: TideColors.accent,
                style: TideText.title(size: 14.5),
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: 'Search history',
                  hintStyle: TideText.title(
                    size: 14.5,
                    color: TideColors.textAt(0.33),
                  ),
                ),
              ),
            ),
            if (onClear != null)
              _QuietX(onTap: onClear!, size: 32),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: TideText.display(23)),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: TideText.body()),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

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
