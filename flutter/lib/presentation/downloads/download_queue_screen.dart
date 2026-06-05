import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/download/download_repository.dart';

/// Mihon's "Download queue" screen. Lists the currently-running download
/// (if any) followed by everything still queued, with a per-row cancel
/// button for queued items and a "Clear queue" action in the app bar.
///
/// Progress percentage is surfaced via the repository's broadcast event
/// stream — we just rebuild on every event since the snapshot is small.
class DownloadQueueScreen extends ConsumerStatefulWidget {
  const DownloadQueueScreen({super.key});

  @override
  ConsumerState<DownloadQueueScreen> createState() =>
      _DownloadQueueScreenState();
}

class _DownloadQueueScreenState extends ConsumerState<DownloadQueueScreen> {
  StreamSubscription<DownloadEvent>? _sub;
  // ChapterId -> last reported 0..1 progress. Stale rows are pruned when
  // the snapshot drops them.
  final Map<int, double> _progress = {};
  // ChapterId -> (downloaded, total) page counts for the "x/y" label.
  final Map<int, (int, int)> _pageCounts = {};

  @override
  void initState() {
    super.initState();
    final repo = ref.read(downloadRepositoryProvider);
    _sub = repo.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(DownloadEvent ev) {
    if (!mounted) return;
    setState(() {
      switch (ev.state) {
        case DownloadState.downloading:
          if (ev.progress != null) _progress[ev.chapterId] = ev.progress!;
          if (ev.downloadedPages != null && ev.totalPages != null) {
            _pageCounts[ev.chapterId] = (ev.downloadedPages!, ev.totalPages!);
          }
        case DownloadState.completed:
        case DownloadState.failed:
        case DownloadState.deleted:
          _progress.remove(ev.chapterId);
          _pageCounts.remove(ev.chapterId);
        case DownloadState.queued:
        case DownloadState.queuePaused:
        case DownloadState.queueResumed:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(downloadRepositoryProvider);
    final items = repo.snapshot();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download queue'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: Icon(
                repo.isPaused ? Icons.play_arrow : Icons.pause,
              ),
              tooltip: repo.isPaused ? 'Resume queue' : 'Pause queue',
              onPressed: () {
                if (repo.isPaused) {
                  repo.resumeQueue();
                } else {
                  repo.pauseQueue();
                }
              },
            ),
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear queue',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear download queue?'),
                    content: const Text(
                      'Queued chapters will be removed. The currently '
                      'downloading chapter will finish.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final removed = repo.clearQueue();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(removed == 1
                          ? 'Removed 1 chapter'
                          : 'Removed $removed chapters'),
                    ),
                  );
                }
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? const _EmptyQueue()
          : Column(
              children: [
                if (repo.isPaused)
                  Material(
                    color:
                        Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pause_circle_outline, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Queue paused — the running chapter will '
                              'finish, but no further jobs will start.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _buildBody(context, repo, items)),
              ],
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DownloadRepository repo,
    List<ActiveDownload> items,
  ) {
    // Snapshot orders running-first, then queued. Split them so the
    // running job stays pinned at the top while only queued rows are
    // dragged.
    final running = items.where((i) => i.current).toList(growable: false);
    final queued = items.where((i) => !i.current).toList(growable: false);
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      header: running.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in running) _buildTile(item, draggable: false),
                const Divider(height: 1),
              ],
            ),
      itemCount: queued.length,
      itemBuilder: (context, i) {
        final item = queued[i];
        return _buildTile(
          item,
          draggable: true,
          dragIndex: i,
          key: ValueKey<int>(item.chapter.id),
        );
      },
      onReorderItem: (oldIdx, newIdx) {
        // onReorderItem already adjusts newIdx to the index after the
        // dragged tile is removed — we can drop the shift the older
        // onReorder callback needed.
        repo.reorderQueue(queued[oldIdx].chapter.id, newIdx);
      },
    );
  }

  Widget _buildTile(
    ActiveDownload item, {
    required bool draggable,
    int? dragIndex,
    Key? key,
  }) {
    final progress = _progress[item.chapter.id];
    // Prefer the live event count; fall back to the snapshot's counts so a
    // freshly opened screen still shows "x/y" before the next event.
    final counts = _pageCounts[item.chapter.id] ??
        (item.totalPages > 0
            ? (item.downloadedPages, item.totalPages)
            : null);
    final repo = ref.read(downloadRepositoryProvider);
    return ListTile(
      key: key,
      leading: item.current
          ? const Icon(Icons.downloading)
          : const Icon(Icons.hourglass_empty),
      title: Text(
        item.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.chapter.name.isEmpty
                ? 'Chapter ${item.chapter.chapterNumber}'
                : item.chapter.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.current && progress != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
            if (counts != null) ...[
              const SizedBox(height: 4),
              Text(
                '${counts.$1}/${counts.$2}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ] else if (item.current) ...[
            const SizedBox(height: 4),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      trailing: item.current
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: () => repo.cancelQueued(item.chapter.id),
                ),
                if (draggable && dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('No downloads in progress.'),
          ],
        ),
      ),
    );
  }
}
