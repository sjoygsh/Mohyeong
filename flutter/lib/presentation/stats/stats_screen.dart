import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history/history_repository.dart';
import '../../data/library/library_repository.dart';
import '../../data/track/track_repository.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/library/model/library_item.dart';

/// Mihon-equivalent Statistics screen. Pulls one snapshot from
/// `libraryView` + the cumulative read duration from `history`, then
/// renders headline totals plus a per-tracker score breakdown.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryRepo = ref.watch(libraryRepositoryProvider);
    final historyRepo = ref.watch(historyRepositoryProvider);
    final trackRepo = ref.watch(trackRepositoryProvider);
    final registry = ref.watch(trackerRegistryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<_Stats>(
        future: _load(libraryRepo, historyRepo, trackRepo, registry),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Failed to load stats: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snap.data!;
          return ListView(
            children: [
              _Section(title: 'Library'),
              _StatTile(
                icon: Icons.collections_bookmark_outlined,
                label: 'Total manga',
                value: '${s.mangaCount}',
              ),
              _StatTile(
                icon: Icons.menu_book_outlined,
                label: 'Total chapters',
                value: '${s.totalChapters}',
              ),
              _StatTile(
                icon: Icons.done_all,
                label: 'Read chapters',
                value: '${s.readChapters}',
              ),
              _StatTile(
                icon: Icons.remove_done,
                label: 'Unread chapters',
                value: '${s.unreadChapters}',
              ),
              _StatTile(
                icon: Icons.bookmark_outline,
                label: 'Bookmarked chapters',
                value: '${s.bookmarkedChapters}',
              ),
              _StatTile(
                icon: Icons.check_circle_outline,
                label: 'Completed manga (locally)',
                value: '${s.completedManga}',
              ),
              _StatTile(
                icon: Icons.track_changes,
                label: 'Tracked manga',
                value: '${s.trackedManga}',
              ),
              _Section(title: 'Sources & categories'),
              _StatTile(
                icon: Icons.dns_outlined,
                label: 'Sources in library',
                value: '${s.sourceCount}',
              ),
              _StatTile(
                icon: Icons.folder_outlined,
                label: 'Categories in use',
                value: '${s.categoryCount}',
              ),
              _Section(title: 'Time'),
              _StatTile(
                icon: Icons.timer_outlined,
                label: 'Total time read',
                value: _formatDuration(s.totalReadMs),
              ),
              _StatTile(
                icon: Icons.av_timer,
                label: 'Average per manga',
                value: s.mangaCount == 0
                    ? '0 min'
                    : _formatDuration(s.totalReadMs ~/ s.mangaCount),
              ),
              if (s.trackScores.isNotEmpty) ...[
                _Section(title: 'Track scores'),
                _StatTile(
                  icon: Icons.star_rate,
                  label: 'Mean score (all trackers)',
                  value: _formatScore(s.overallMeanScore),
                ),
                for (final group in s.trackScores)
                  _StatTile(
                    icon: Icons.star_border,
                    label: group.trackerName,
                    value:
                        '${_formatScore(group.meanScore)}  (${group.ratedCount})',
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _formatDuration(int ms) {
    final totalMin = ms ~/ 60000;
    if (totalMin == 0) return '0 min';
    final days = totalMin ~/ (60 * 24);
    final hours = (totalMin % (60 * 24)) ~/ 60;
    final mins = totalMin % 60;
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (mins > 0 || parts.isEmpty) parts.add('${mins}m');
    return parts.join(' ');
  }

  // Scores are normalised to the 0..10 scale at the data layer (Kitsu's
  // 0..20 native scale, for example, is halved on the way in). One
  // decimal is enough to keep aggregate means readable without showing
  // spurious precision.
  static String _formatScore(double score) =>
      '${score.toStringAsFixed(1)} / 10';
}

Future<_Stats> _load(
  LibraryRepository library,
  HistoryRepository history,
  TrackRepository tracks,
  TrackerRegistry registry,
) async {
  // Pull the first emission of the library stream — this is a one-shot
  // snapshot for the screen, not a live feed.
  final items = await library.watchAll().first;
  final totalReadMs = await history.totalReadDurationMs();
  final trackRows = await tracks.getAll();
  // Tracked-in-library count: only intersect with manga that are
  // currently favourited so a tracker row left over from a removed
  // series doesn't inflate the number.
  final libraryIds = {for (final i in items) i.manga.id};
  final libraryTrackRows =
      trackRows.where((t) => libraryIds.contains(t.mangaId)).toList(
            growable: false,
          );
  final trackedManga =
      libraryTrackRows.map((t) => t.mangaId).toSet().length;
  // Group track rows by trackerId for the score breakdown. Only count
  // rows with a positive score — Mihon treats `0.0` as "no score set"
  // and including those would tank every average.
  final byTracker = <int, List<double>>{};
  for (final t in libraryTrackRows) {
    if (t.score <= 0) continue;
    byTracker.putIfAbsent(t.trackerId, () => []).add(t.score);
  }
  final groups = <_TrackerScoreGroup>[];
  for (final entry in byTracker.entries) {
    final scores = entry.value;
    if (scores.isEmpty) continue;
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    // Unknown ids fall through to a synthetic label — happens when a
    // tracker was uninstalled but the manga_sync row was kept.
    final name =
        registry.byId(entry.key)?.name ?? 'Tracker ${entry.key}';
    groups.add(_TrackerScoreGroup(
      trackerName: name,
      meanScore: mean,
      ratedCount: scores.length,
    ));
  }
  groups.sort((a, b) => a.trackerName.compareTo(b.trackerName));
  final allScores = byTracker.values.expand((l) => l).toList(growable: false);
  final overallMean = allScores.isEmpty
      ? 0.0
      : allScores.reduce((a, b) => a + b) / allScores.length;
  return _Stats.fromItems(items, totalReadMs, trackedManga, groups, overallMean);
}

class _Stats {
  const _Stats({
    required this.mangaCount,
    required this.totalChapters,
    required this.readChapters,
    required this.unreadChapters,
    required this.bookmarkedChapters,
    required this.completedManga,
    required this.totalReadMs,
    required this.sourceCount,
    required this.categoryCount,
    required this.trackedManga,
    required this.trackScores,
    required this.overallMeanScore,
  });

  final int mangaCount;
  final int totalChapters;
  final int readChapters;
  final int unreadChapters;
  final int bookmarkedChapters;
  final int completedManga;
  final int totalReadMs;
  final int sourceCount;
  final int categoryCount;
  final int trackedManga;
  final List<_TrackerScoreGroup> trackScores;
  final double overallMeanScore;

  factory _Stats.fromItems(
    List<LibraryItem> items,
    int readMs,
    int trackedManga,
    List<_TrackerScoreGroup> trackScores,
    double overallMeanScore,
  ) {
    var totalChapters = 0;
    var readChapters = 0;
    var unreadChapters = 0;
    var bookmarkedChapters = 0;
    var completedManga = 0;
    final sources = <int>{};
    final categories = <int>{};
    for (final i in items) {
      totalChapters += i.totalCount;
      readChapters += i.readCount;
      unreadChapters += i.unreadCount;
      bookmarkedChapters += i.bookmarkCount;
      if (i.totalCount > 0 && i.readCount == i.totalCount) {
        completedManga++;
      }
      sources.add(i.manga.source);
      // Category id 0 is Mihon's implicit "Default" bucket assigned to
      // every uncategorised manga — skip it so a fresh library reads as
      // "0 categories in use" instead of "1".
      for (final c in i.categoryIds) {
        if (c != 0) categories.add(c);
      }
    }
    return _Stats(
      mangaCount: items.length,
      totalChapters: totalChapters,
      readChapters: readChapters,
      unreadChapters: unreadChapters,
      bookmarkedChapters: bookmarkedChapters,
      completedManga: completedManga,
      totalReadMs: readMs,
      sourceCount: sources.length,
      categoryCount: categories.length,
      trackedManga: trackedManga,
      trackScores: trackScores,
      overallMeanScore: overallMeanScore,
    );
  }
}

class _TrackerScoreGroup {
  const _TrackerScoreGroup({
    required this.trackerName,
    required this.meanScore,
    required this.ratedCount,
  });

  final String trackerName;
  final double meanScore;
  final int ratedCount;
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
