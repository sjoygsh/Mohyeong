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
        case DownloadState.networkWaiting:
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
        // Title carries a count pill of the queued chapters, mirroring
        // Kotlin's DownloadQueueScreen.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Download queue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _CountPill(count: items.length),
              ),
          ],
        ),
        actions: [
          if (items.isNotEmpty)
            PopupMenuButton<_QueueSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onSelected: (s) => _applySort(repo, s),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _QueueSort.dateNewest,
                  child: Text('By upload date · Newest'),
                ),
                PopupMenuItem(
                  value: _QueueSort.dateOldest,
                  child: Text('By upload date · Oldest'),
                ),
                PopupMenuItem(
                  value: _QueueSort.numberAsc,
                  child: Text('By chapter number · Ascending'),
                ),
                PopupMenuItem(
                  value: _QueueSort.numberDesc,
                  child: Text('By chapter number · Descending'),
                ),
              ],
            ),
          if (items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (_) => _confirmClearQueue(context, repo),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cancel_all', child: Text('Cancel all')),
              ],
            ),
        ],
      ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: Icon(repo.isPaused ? Icons.play_arrow : Icons.pause),
              label: Text(repo.isPaused ? 'Resume' : 'Pause'),
              onPressed: () {
                if (repo.isPaused) {
                  repo.resumeQueue();
                } else {
                  repo.pauseQueue();
                }
              },
            ),
      body: items.isEmpty
          ? const _EmptyQueue()
          : Column(
              children: [
                if (repo.isPaused)
                  _QueueBanner(
                    icon: Icons.pause_circle_outline,
                    text: 'Queue paused — the running chapter will finish, '
                        'but no further jobs will start.',
                  )
                else if (repo.isWaitingForNetwork)
                  _QueueBanner(
                    icon: Icons.wifi_off,
                    text: 'Waiting for an allowed network — downloads only '
                        'run over Wi-Fi while that setting is on.',
                  ),
                Expanded(child: _buildBody(context, repo, items)),
              ],
            ),
    );
  }

  void _applySort(DownloadRepository repo, _QueueSort sort) {
    switch (sort) {
      case _QueueSort.dateNewest:
        repo.sortQueue((a, b) => b.dateUpload.compareTo(a.dateUpload));
      case _QueueSort.dateOldest:
        repo.sortQueue((a, b) => a.dateUpload.compareTo(b.dateUpload));
      case _QueueSort.numberAsc:
        repo.sortQueue((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
      case _QueueSort.numberDesc:
        repo.sortQueue((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
    }
  }

  Future<void> _confirmClearQueue(
    BuildContext context,
    DownloadRepository repo,
  ) async {
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
  }

  Widget _buildBody(
    BuildContext context,
    DownloadRepository repo,
    List<ActiveDownload> items,
  ) {
    // Snapshot orders running, then errored, then queued. Pin the running
    // and errored rows at the top; the queued remainder renders grouped by
    // manga (Kotlin's DownloadHeaderItem: an expandable series header with
    // its chapters beneath and series-level move-to-top / cancel actions —
    // replaces the old flat drag-to-reorder list; ordering is still
    // available via the Sort menu + "Move series to top").
    final pinned = items.where((i) => i.current || i.errored)
        .toList(growable: false);
    final queued = items
        .where((i) => !i.current && !i.errored)
        .toList(growable: false);

    // Bucket queued rows by manga in order of first appearance, preserving
    // each chapter's queue order within its group.
    final groupOrder = <int>[];
    final groups = <int, List<ActiveDownload>>{};
    for (final item in queued) {
      final id = item.manga.id;
      (groups[id] ??= (() {
        groupOrder.add(id);
        return <ActiveDownload>[];
      })())
          .add(item);
    }

    return ListView(
      children: [
        for (final item in pinned) _buildTile(item),
        if (pinned.isNotEmpty && groupOrder.isNotEmpty)
          const Divider(height: 1),
        for (final mangaId in groupOrder)
          _buildGroup(repo, groups[mangaId]!),
      ],
    );
  }

  /// One manga's queued chapters under an expandable series header.
  Widget _buildGroup(DownloadRepository repo, List<ActiveDownload> group) {
    final manga = group.first.manga;
    final n = group.length;
    return ExpansionTile(
      key: PageStorageKey<int>(manga.id),
      initiallyExpanded: true,
      shape: const Border(),
      title: Text(
        manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$n chapter${n == 1 ? '' : 's'}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'top':
                  // Walk the group's chapters into the front of the queue,
                  // preserving their relative order (Kotlin "Move series
                  // to top").
                  for (final (i, item) in group.indexed) {
                    repo.reorderQueue(item.chapter.id, i);
                  }
                case 'cancel':
                  for (final item in group) {
                    repo.cancel(item.chapter.id);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'top', child: Text('Move series to top')),
              PopupMenuItem(value: 'cancel', child: Text('Cancel all')),
            ],
          ),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        for (final item in group) _buildTile(item, inGroup: true),
      ],
    );
  }

  Widget _buildTile(
    ActiveDownload item, {
    bool inGroup = false,
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
    final chapterLabel = item.chapter.name.isEmpty
        ? 'Chapter ${item.chapter.chapterNumber}'
        : item.chapter.name;
    return ListTile(
      key: key,
      // Grouped rows sit under their series header — indent and lead with
      // the chapter, not the manga title.
      contentPadding:
          inGroup ? const EdgeInsetsDirectional.only(start: 32, end: 16) : null,
      leading: item.errored
          ? Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            )
          : item.current
              ? const Icon(Icons.downloading)
              : const Icon(Icons.hourglass_empty),
      title: Text(
        inGroup ? chapterLabel : item.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!inGroup)
            Text(
              chapterLabel,
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
          ] else if (item.errored) ...[
            const SizedBox(height: 4),
            Text(
              'Download error',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.errored)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry',
              onPressed: () => repo.retry(item.chapter.id),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => repo.cancel(item.chapter.id),
          ),
        ],
      ),
    );
  }
}

/// Sort options for the download queue, mirroring Kotlin's Sort menu.
enum _QueueSort { dateNewest, dateOldest, numberAsc, numberDesc }

/// Small rounded count badge shown next to the app-bar title (Kotlin's
/// Pill).
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _QueueBanner extends StatelessWidget {
  const _QueueBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
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
            const Text('No downloads'),
          ],
        ),
      ),
    );
  }
}
