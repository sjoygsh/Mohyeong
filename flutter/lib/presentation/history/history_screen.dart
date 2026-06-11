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
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear history',
              onPressed: () => _confirmClearAll(context, repo),
            ),
          ],
        ),
        body: StreamBuilder<List<HistoryWithContext>>(
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
              return const Center(child: Text('Nothing read recently'));
            }
            // Substring match on manga title — same lightweight
            // case-insensitive contains the Library search uses.
            // Day grouping runs after filtering so the day
            // headers only reflect the visible rows.
            final q = _query.toLowerCase();
            final filtered = q.isEmpty
                ? entries
                : entries
                    .where((e) => e.mangaTitle.toLowerCase().contains(q))
                    .toList(growable: false);
            if (filtered.isEmpty) {
              return const Center(child: Text('No results found'));
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
    );
  }

  Future<void> _confirmClearAll(
      BuildContext context, HistoryRepository repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove everything'),
        content: const Text('Are you sure? All history will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.removeAll();
    }
  }
}

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

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final HistoryWithContext entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readAt = entry.readAt;
    final relative = ref.watch(relativeTimestampsProvider);
    final datePattern = ref.watch(dateFormatProvider);
    final time = readAt == null
        ? ''
        : formatTimestamp(readAt, relative: relative, pattern: datePattern);
    // Mirrors Kotlin's `recent_manga_time` ("Ch. %1$s - %2$s"): the chapter
    // *number* plus the read time, falling back to just the time when the
    // number is unset (-1).
    final subtitle = entry.chapterNumber > -1
        ? 'Ch. ${_formatChapterNumber(entry.chapterNumber)} - $time'
        : time;
    return ListTile(
      // Cover tap opens the manga details screen (Kotlin onClickCover);
      // tapping the rest of the row resumes reading (Kotlin onClickResume).
      leading: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(mangaId: entry.mangaId),
          ),
        ),
        child: _Thumb(url: entry.thumbnailUrl),
      ),
      title: Text(
        entry.mangaTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            mangaId: entry.mangaId,
            chapterId: entry.chapterId,
          ),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Remove',
        onPressed: () => _confirmDelete(context, ref),
      ),
    );
  }

  /// Per-entry delete confirmation. Mirrors Kotlin `HistoryDeleteDialog`:
  /// removes this entry's read date, or — when the checkbox is ticked —
  /// resets every chapter's history for this manga.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(historyRepositoryProvider);
    var removeEverything = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Remove'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will remove the read date of this chapter. '
                'Are you sure?',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Reset all chapters for this entry'),
                value: removeEverything,
                onChanged: (v) =>
                    setState(() => removeEverything = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove'),
            ),
          ],
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

/// Formats a chapter number the way Kotlin's `formatChapterNumber` does:
/// drop a trailing ".0" for whole numbers, otherwise keep the decimals.
String _formatChapterNumber(double n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toString();
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
          cacheWidth: 180,
          url: url!,
          fit: BoxFit.cover,
          placeholder: (_) => fallback,
          errorWidget: (_, _) => fallback,
        ),
      ),
    );
  }
}
