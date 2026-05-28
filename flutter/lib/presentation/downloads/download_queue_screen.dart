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
        case DownloadState.completed:
        case DownloadState.failed:
        case DownloadState.deleted:
          _progress.remove(ev.chapterId);
        case DownloadState.queued:
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
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                final progress = _progress[item.chapter.id];
                return ListTile(
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
                      ] else if (item.current) ...[
                        const SizedBox(height: 4),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                  trailing: item.current
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel',
                          onPressed: () {
                            repo.cancelQueued(item.chapter.id);
                          },
                        ),
                );
              },
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
