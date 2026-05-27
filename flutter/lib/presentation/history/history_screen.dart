import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history/history_repository.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

/// History tab. Streams the most recently read chapters with their
/// manga context attached. The header shows the cumulative reading time
/// (mirrors the Kotlin "Total time read" stat).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(historyRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
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
                  return const Center(child: Text('No reading history yet.'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _HistoryTile(entry: entries[i]),
                );
              },
            ),
          ),
        ],
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryWithContext entry;

  @override
  Widget build(BuildContext context) {
    final readAt = entry.readAt;
    final subtitle = readAt == null
        ? entry.chapterName
        : '${entry.chapterName} • ${_relative(readAt)}';
    return ListTile(
      leading: _Thumb(url: entry.thumbnailUrl),
      title: Text(
        entry.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(mangaId: entry.mangaId),
          ),
        );
      },
    );
  }

  static String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
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
