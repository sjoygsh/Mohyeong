import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history/history_repository.dart';
import '../../data/library/library_repository.dart';
import '../../domain/library/model/library_item.dart';

/// Mihon-equivalent Statistics screen. Pulls one snapshot from
/// `libraryView` + the cumulative read duration from `history`, then
/// renders headline totals. Per-manga / track-score breakdowns are
/// deliberately deferred — they need joins through the track tables
/// that aren't pre-aggregated yet.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryRepo = ref.watch(libraryRepositoryProvider);
    final historyRepo = ref.watch(historyRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: FutureBuilder<_Stats>(
        future: _load(libraryRepo, historyRepo),
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
              _Section(title: 'Time'),
              _StatTile(
                icon: Icons.timer_outlined,
                label: 'Total time read',
                value: _formatDuration(s.totalReadMs),
              ),
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
}

Future<_Stats> _load(
  LibraryRepository library,
  HistoryRepository history,
) async {
  // Pull the first emission of the library stream — this is a one-shot
  // snapshot for the screen, not a live feed.
  final items = await library.watchAll().first;
  final totalReadMs = await history.totalReadDurationMs();
  return _Stats.fromItems(items, totalReadMs);
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
  });

  final int mangaCount;
  final int totalChapters;
  final int readChapters;
  final int unreadChapters;
  final int bookmarkedChapters;
  final int completedManga;
  final int totalReadMs;

  factory _Stats.fromItems(List<LibraryItem> items, int readMs) {
    var totalChapters = 0;
    var readChapters = 0;
    var unreadChapters = 0;
    var bookmarkedChapters = 0;
    var completedManga = 0;
    for (final i in items) {
      totalChapters += i.totalCount;
      readChapters += i.readCount;
      unreadChapters += i.unreadCount;
      bookmarkedChapters += i.bookmarkCount;
      if (i.totalCount > 0 && i.readCount == i.totalCount) {
        completedManga++;
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
    );
  }
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
