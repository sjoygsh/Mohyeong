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

/// Statistics screen — 1:1 with Mihon's `StatsScreenContent`: four
/// `SectionCard`s (Overview / Entries / Chapters / Trackers), each laid out
/// as a `Row` of equal-weight metric items. The Overview row shows large
/// figures with primary-tinted icons; the rest are compact figure/label
/// pairs. Data is a one-shot snapshot pulled when the screen opens.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  // Source status value matching SManga.COMPLETED.
  static const int _statusCompleted = 2;
  // LocalSource numeric id (slug '0' → 0).
  static const int _localSourceId = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryRepo = ref.watch(libraryRepositoryProvider);
    final historyRepo = ref.watch(historyRepositoryProvider);
    final trackRepo = ref.watch(trackRepositoryProvider);
    final registry = ref.watch(trackerRegistryProvider);
    final downloadRepo = ref.watch(downloadRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<_Stats>(
        future: _load(libraryRepo, historyRepo, trackRepo, registry, downloadRepo),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Failed to load stats: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snap.data!;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionCard(
                title: 'Overview',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OverviewItem(
                      icon: Icons.collections_bookmark_outlined,
                      value: '${s.libraryMangaCount}',
                      label: 'In library',
                    ),
                    _OverviewItem(
                      icon: Icons.schedule_outlined,
                      value: _formatDuration(s.totalReadMs),
                      label: 'Read duration',
                    ),
                    _OverviewItem(
                      icon: Icons.local_library_outlined,
                      value: '${s.completedMangaCount}',
                      label: 'Completed entries',
                    ),
                  ],
                ),
              ),
              _SectionCard(
                title: 'Entries',
                child: Row(
                  children: [
                    _StatItem('${s.globalUpdateItemCount}', 'In global update'),
                    _StatItem('${s.startedMangaCount}', 'Started'),
                    _StatItem('${s.localMangaCount}', 'Local'),
                  ],
                ),
              ),
              _SectionCard(
                title: 'Chapters',
                child: Row(
                  children: [
                    _StatItem('${s.totalChapterCount}', 'Total'),
                    _StatItem('${s.readChapterCount}', 'Read'),
                    _StatItem('${s.downloadCount}', 'Downloaded'),
                  ],
                ),
              ),
              _SectionCard(
                title: 'Trackers',
                child: Row(
                  children: [
                    _StatItem('${s.trackedTitleCount}', 'Tracked entries'),
                    _StatItem(_formatMeanScore(s), 'Mean score'),
                    _StatItem('${s.trackerCount}', 'Used'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
  final included =
      _parseIds(prefs.getStringList('library_update_categories'));
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
      if (i.manga.status == StatsScreen._statusCompleted && i.unreadCount == 0) {
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
      final skip = (restrictions.contains(MangaUpdateRestriction.nonCompleted) &&
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

/// Section title (titleSmall) + an ElevatedCard with an extra-large rounded
/// shape, mirroring Mihon's `SectionCard`.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: IntrinsicHeight(child: child),
          ),
        ),
      ],
    );
  }
}

/// Large figure + label with a primary-tinted icon below (Overview row).
class _OverviewItem extends StatelessWidget {
  const _OverviewItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 8),
          Icon(icon, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

/// Compact figure + label (Entries / Chapters / Trackers rows).
class _StatItem extends StatelessWidget {
  const _StatItem(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}
