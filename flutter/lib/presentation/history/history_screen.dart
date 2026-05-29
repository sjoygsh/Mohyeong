import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history/history_repository.dart';
import '../../data/preferences/appearance_preferences.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';
import '../reader/reader_screen.dart';
import '../util/timestamp_format.dart';

/// History tab. Streams the most recently read chapters with their
/// manga context attached. The header shows the cumulative reading time
/// (mirrors the Kotlin "Total time read" stat).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(historyRepositoryProvider);

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search history',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                )
              : const Text('History'),
          leading: _searching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _closeSearch,
                )
              : null,
          actions: [
            if (_searching && _query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Clear query',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            else if (!_searching)
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search history',
                onPressed: _openSearch,
              ),
            PopupMenuButton<_HistoryMenuAction>(
              onSelected: (action) {
                if (action == _HistoryMenuAction.clearAll) {
                  _confirmClearAll(context, repo);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HistoryMenuAction.clearAll,
                  child: Text('Clear history'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _DurationHeader(repo: repo),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<HistoryWithContext>>(
                stream: repo.watchRecent(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snap.data!;
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No reading history yet.'),
                    );
                  }
                  // Substring match on manga title — same lightweight
                  // case-insensitive contains the Library search uses.
                  // Day grouping runs after filtering so the day
                  // headers only reflect the visible rows.
                  final q = _query.toLowerCase();
                  final filtered = q.isEmpty
                      ? entries
                      : entries
                          .where(
                              (e) => e.mangaTitle.toLowerCase().contains(q))
                          .toList(growable: false);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No history matches the query.'),
                    );
                  }
                  final rows = _groupByDay(filtered);
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      if (row is _HeaderRow) {
                        return _DayHeader(label: row.label);
                      }
                      return _HistoryTile(entry: (row as _EntryRow).entry);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, HistoryRepository repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'Every read entry will be removed. This does not affect '
          'downloaded chapters or your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.removeAll();
    }
  }
}

enum _HistoryMenuAction { clearAll }

enum _HistoryRowAction { openDetails, removeEntry, resetManga }

sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.label);
  final String label;
}

class _EntryRow extends _Row {
  const _EntryRow(this.entry);
  final HistoryWithContext entry;
}

/// Walks the entries in stream-order (most recent first) and emits a
/// `_HeaderRow` whenever the day label changes. Entries with `readAt
/// == null` are bucketed under "Unknown".
List<_Row> _groupByDay(List<HistoryWithContext> entries) {
  final rows = <_Row>[];
  String? lastLabel;
  for (final e in entries) {
    final label = _dayLabel(e.readAt);
    if (label != lastLabel) {
      rows.add(_HeaderRow(label));
      lastLabel = label;
    }
    rows.add(_EntryRow(e));
  }
  return rows;
}

String _dayLabel(DateTime? t) {
  if (t == null) return 'Unknown';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
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

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _DurationHeader extends StatelessWidget {
  const _DurationHeader({required this.repo});

  final HistoryRepository repo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: repo.totalReadDurationMs(),
      builder: (context, snap) {
        final ms = snap.data ?? 0;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 12),
              Text(
                'Total time read: ${_formatDuration(ms)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(int ms) {
    final totalMin = ms ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h == 0) return '$m min';
    return '${h}h ${m}m';
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final HistoryWithContext entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readAt = entry.readAt;
    final relative = ref.watch(relativeTimestampsProvider);
    final subtitle = readAt == null
        ? entry.chapterName
        : '${entry.chapterName} • ${formatTimestamp(readAt, relative: relative)}';
    return ListTile(
      leading: _Thumb(url: entry.thumbnailUrl),
      title: Text(
        entry.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Mihon's behaviour: tap a history row to resume reading the
      // chapter that row represents, rather than detouring through the
      // manga details screen. Long-press exposes the per-row delete +
      // per-manga reset entry points.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            mangaId: entry.mangaId,
            chapterId: entry.chapterId,
          ),
        ),
      ),
      onLongPress: () => _showRowMenu(context, ref),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Remove from history',
        onPressed: () => ref
            .read(historyRepositoryProvider)
            .removeById(entry.historyId),
      ),
    );
  }

  Future<void> _showRowMenu(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(historyRepositoryProvider);
    final action = await showModalBottomSheet<_HistoryRowAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Open manga details'),
              onTap: () =>
                  Navigator.of(ctx).pop(_HistoryRowAction.openDetails),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from history'),
              onTap: () =>
                  Navigator.of(ctx).pop(_HistoryRowAction.removeEntry),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Reset history for this manga'),
              onTap: () =>
                  Navigator.of(ctx).pop(_HistoryRowAction.resetManga),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _HistoryRowAction.openDetails:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(mangaId: entry.mangaId),
          ),
        );
      case _HistoryRowAction.removeEntry:
        await repo.removeById(entry.historyId);
      case _HistoryRowAction.resetManga:
        await repo.resetByMangaId(entry.mangaId);
    }
  }

}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 40,
      height: 56,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book, size: 20),
    );
    if (url == null || url!.isEmpty) return fallback;
    return SizedBox(
      width: 40,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SourceImage(
          url: url!,
          fit: BoxFit.cover,
          placeholder: (_) => fallback,
          errorWidget: (_, _) => fallback,
        ),
      ),
    );
  }
}
