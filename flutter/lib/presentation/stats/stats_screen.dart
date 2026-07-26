// ===========================================================================
// Tide statistics.
//
// Four groups of three numbers. The three that answer "how much of this have I
// actually done" lead at display size; the rest are panels of quiet figures.
// Chapters carries a lit underline for the read ratio, because "1,284 total /
// 903 read" is a fraction the eye should not have to compute.
//
// Every figure is Mihon's, computed the same way — this is a new presentation
// of the same snapshot, not a new set of statistics.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/download/download_repository.dart';
import '../../data/history/history_repository.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_update_preference.dart';
import '../../data/track/track_repository.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/library/model/library_item.dart';
import '../tide/tide.dart';

/// Statistics screen — the same four groups Mihon's `StatsScreenContent`
/// shows (Overview / Entries / Chapters / Trackers). Data is a one-shot
/// snapshot pulled when the screen opens.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  // Source status value matching SManga.COMPLETED.
  static const int _statusCompleted = 2;
  // LocalSource numeric id (slug '0' → 0).
  static const int _localSourceId = 0;

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  /// Held rather than started in build: the load runs a library snapshot, a
  /// track query and a login probe per tracker, and building it inline
  /// re-ran the lot on every rebuild.
  late final Future<_Stats> _future = _load(
    ref.read(libraryRepositoryProvider),
    ref.read(historyRepositoryProvider),
    ref.read(trackRepositoryProvider),
    ref.read(trackerRegistryProvider),
    ref.read(downloadRepositoryProvider),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: 0.34)),
          Positioned.fill(
            child: TideRise(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TideHeader(title: 'Statistics'),
                  Expanded(
                    child: FutureBuilder<_Stats>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _Note('Failed to load stats: ${snap.error}');
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: TideColors.accent,
                            ),
                          );
                        }
                        return _body(snap.data!);
                      },
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

  Widget _body(_Stats s) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // The headline three. Read duration first: it is the only figure here
        // that measures what you did rather than what you have.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TideGlass(
            radius: 22,
            tintTop: 0.085,
            tintBottom: 0.03,
            highlight: 0.15,
            border: 0.10,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TIME READ',
                  style: TideText.kicker(size: 10.5)
                      .copyWith(letterSpacing: 1.7),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDuration(s.totalReadMs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.display(34),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _Headline(
                      icon: Icons.collections_bookmark_outlined,
                      value: '${s.libraryMangaCount}',
                      label: 'In library',
                    ),
                    const SizedBox(width: 14),
                    _Headline(
                      icon: Icons.local_library_outlined,
                      value: '${s.completedMangaCount}',
                      label: 'Completed',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const TideSectionHeader(label: 'Entries'),
        _Panel(
          cells: [
            ('${s.globalUpdateItemCount}', 'In global update'),
            ('${s.startedMangaCount}', 'Started'),
            ('${s.localMangaCount}', 'Local'),
          ],
        ),
        TideSectionHeader(
          label: 'Chapters',
          trailing: s.totalChapterCount == 0
              ? null
              : '${(s.readChapterCount / s.totalChapterCount * 100).round()}% read',
        ),
        _Panel(
          cells: [
            ('${s.totalChapterCount}', 'Total'),
            ('${s.readChapterCount}', 'Read'),
            ('${s.downloadCount}', 'Downloaded'),
          ],
          // The accent as a line: the fraction, drawn rather than computed.
          ratio: s.totalChapterCount == 0
              ? null
              : s.readChapterCount / s.totalChapterCount,
        ),
        const TideSectionHeader(label: 'Trackers'),
        _Panel(
          cells: [
            ('${s.trackedTitleCount}', 'Tracked'),
            (_formatMeanScore(s), 'Mean score'),
            ('${s.trackerCount}', 'Used'),
          ],
        ),
      ],
    );
  }

  // Mirrors Mihon's `Duration.toDurationString`: "Xd Xh Xm Xs", dropping
  // zero components, hiding minutes once both days and hours are present,
  // hiding seconds once days or hours are present. Blank → "None".
  static String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final days = totalSec ~/ 86400;
    final hours = (totalSec % 86400) ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    final seconds = totalSec % 60;
    final parts = <String>[];
    if (days != 0) parts.add('${days}d');
    if (hours != 0) parts.add('${hours}h');
    if (minutes != 0 && (days == 0 || hours == 0)) parts.add('${minutes}m');
    if (seconds != 0 && days == 0 && hours == 0) parts.add('${seconds}s');
    return parts.isEmpty ? 'None' : parts.join(' ');
  }

  // Mihon: "%.2f ★" (English locale) when there is at least one tracked
  // title with a score, otherwise the not-applicable string.
  static String _formatMeanScore(_Stats s) {
    if (s.trackedTitleCount > 0 && !s.meanScore.isNaN) {
      return '${s.meanScore.toStringAsFixed(2)} ★';
    }
    return 'N/A';
  }
}

Future<_Stats> _load(
  LibraryRepository library,
  HistoryRepository history,
  TrackRepository tracks,
  TrackerRegistry registry,
  DownloadRepository downloads,
) async {
  // One-shot snapshot of the library, de-duplicated by manga id (a manga in
  // multiple categories appears once per category in the view).
  final raw = await library.watchAll().first;
  final seen = <int>{};
  final items = <LibraryItem>[];
  for (final i in raw) {
    if (seen.add(i.manga.id)) items.add(i);
  }

  final totalReadMs = await history.totalReadDurationMs();
  final downloadCount = await downloads.totalDownloadedCount();

  // Logged-in trackers: only these count toward "Used" and feed the mean
  // score / tracked-title figures (matches Mihon's loggedInTrackers gate).
  final loggedInIds = <int>{};
  for (final t in registry.all) {
    if (await t.isLoggedIn) loggedInIds.add(t.id);
  }

  // Per-manga track rows restricted to logged-in trackers.
  final libraryIds = {for (final i in items) i.manga.id};
  final allRows = await tracks.getAll();
  final byManga = <int, List<double>>{}; // mangaId -> all logged-in track scores
  for (final r in allRows) {
    if (!libraryIds.contains(r.mangaId)) continue;
    if (!loggedInIds.contains(r.trackerId)) continue;
    byManga.putIfAbsent(r.mangaId, () => []).add(r.score);
  }
  final trackedTitleCount = byManga.length;
  // Mean score: per-manga average of its positive (>0) scores, then the
  // average of those per-manga means. NaN when nothing is scored.
  final perMangaMeans = <double>[];
  for (final scores in byManga.values) {
    final scored = scores.where((v) => v > 0).toList(growable: false);
    if (scored.isEmpty) continue;
    perMangaMeans.add(scored.reduce((a, b) => a + b) / scored.length);
  }
  final meanScore = perMangaMeans.isEmpty
      ? double.nan
      : perMangaMeans.reduce((a, b) => a + b) / perMangaMeans.length;

  // Global-update item count: replicate Mihon's `getGlobalUpdateItemCount`
  // category include/exclude + the three relevant update restrictions
  // (skip-completed, skip-unread, skip-not-started). Prefs read straight
  // from disk so the snapshot reflects the persisted settings.
  final prefs = await SharedPreferences.getInstance();
  final restrictions =
      (prefs.getStringList('library_update_manga_restriction') ??
              const [
                MangaUpdateRestriction.hasUnread,
                MangaUpdateRestriction.nonCompleted,
                MangaUpdateRestriction.nonRead,
                MangaUpdateRestriction.outsideReleasePeriod,
              ])
          .toSet();
  final included = _parseIds(prefs.getStringList('library_update_categories'));
  final excluded =
      _parseIds(prefs.getStringList('library_update_categories_exclude'));

  return _Stats.fromItems(
    items,
    totalReadMs: totalReadMs,
    downloadCount: downloadCount,
    trackedTitleCount: trackedTitleCount,
    meanScore: meanScore,
    trackerCount: loggedInIds.length,
    restrictions: restrictions,
    includedCategories: included,
    excludedCategories: excluded,
  );
}

Set<int> _parseIds(List<String>? raw) =>
    (raw ?? const []).map(int.tryParse).whereType<int>().toSet();

class _Stats {
  const _Stats({
    required this.libraryMangaCount,
    required this.completedMangaCount,
    required this.totalReadMs,
    required this.globalUpdateItemCount,
    required this.startedMangaCount,
    required this.localMangaCount,
    required this.totalChapterCount,
    required this.readChapterCount,
    required this.downloadCount,
    required this.trackedTitleCount,
    required this.meanScore,
    required this.trackerCount,
  });

  final int libraryMangaCount;
  final int completedMangaCount;
  final int totalReadMs;
  final int globalUpdateItemCount;
  final int startedMangaCount;
  final int localMangaCount;
  final int totalChapterCount;
  final int readChapterCount;
  final int downloadCount;
  final int trackedTitleCount;
  final double meanScore;
  final int trackerCount;

  factory _Stats.fromItems(
    List<LibraryItem> items, {
    required int totalReadMs,
    required int downloadCount,
    required int trackedTitleCount,
    required double meanScore,
    required int trackerCount,
    required Set<String> restrictions,
    required Set<int> includedCategories,
    required Set<int> excludedCategories,
  }) {
    var completed = 0;
    var started = 0;
    var local = 0;
    var totalChapters = 0;
    var readChapters = 0;
    var globalUpdate = 0;
    for (final i in items) {
      totalChapters += i.totalCount;
      readChapters += i.readCount;
      final hasStarted = i.readCount > 0;
      if (i.manga.status == StatsScreen._statusCompleted &&
          i.unreadCount == 0) {
        completed++;
      }
      if (hasStarted) started++;
      if (i.manga.source == StatsScreen._localSourceId) local++;

      // Category scope (exclusion wins over inclusion).
      final cats = i.categoryIds;
      final isIncluded =
          includedCategories.isEmpty || cats.any(includedCategories.contains);
      final isExcluded = cats.any(excludedCategories.contains);
      if (!isIncluded || isExcluded) continue;
      // Restriction filter — the entry counts toward the global update only
      // when NONE of the active skip-conditions apply.
      final skip =
          (restrictions.contains(MangaUpdateRestriction.nonCompleted) &&
                  i.manga.status == StatsScreen._statusCompleted) ||
              (restrictions.contains(MangaUpdateRestriction.hasUnread) &&
                  i.unreadCount != 0) ||
              (restrictions.contains(MangaUpdateRestriction.nonRead) &&
                  i.totalCount > 0 &&
                  !hasStarted);
      if (!skip) globalUpdate++;
    }
    return _Stats(
      libraryMangaCount: items.length,
      completedMangaCount: completed,
      totalReadMs: totalReadMs,
      globalUpdateItemCount: globalUpdate,
      startedMangaCount: started,
      localMangaCount: local,
      totalChapterCount: totalChapters,
      readChapterCount: readChapters,
      downloadCount: downloadCount,
      trackedTitleCount: trackedTitleCount,
      meanScore: meanScore,
      trackerCount: trackerCount,
    );
  }
}

/// One of the two secondary headline figures, beside the read duration.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 17, color: TideColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.38,
                    color: TideColors.textBright,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.caption(size: 11, opacity: 0.42),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Three evenly-weighted figures in one pane, optionally underlined with a
/// ratio.
class _Panel extends StatelessWidget {
  const _Panel({required this.cells, this.ratio});

  final List<(String value, String label)> cells;
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TideGlass(
        radius: 20,
        tintTop: 0.085,
        tintBottom: 0.03,
        highlight: 0.15,
        border: 0.10,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  for (final (i, (value, label)) in cells.indexed) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    Expanded(child: _Cell(value: value, label: label)),
                  ],
                ],
              ),
            ),
            if (ratio != null)
              SizedBox(
                height: 3,
                child: Row(
                  children: [
                    Expanded(
                      flex: (ratio!.clamp(0.0, 1.0) * 1000).round(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: TideColors.accent,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  TideColors.accent.withValues(alpha: 0.75),
                              blurRadius: 9,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - ratio!.clamp(0.0, 1.0)) * 1000).round(),
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.38,
              color: TideColors.textBright,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TideText.kicker(size: 9.5).copyWith(letterSpacing: 1.2),
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
