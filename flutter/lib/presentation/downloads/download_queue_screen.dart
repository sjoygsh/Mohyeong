// ===========================================================================
// Tide download queue.
//
// A queue is a thing in motion, so the one row actually moving gets the light:
// the running chapter is a lit pane with its progress drawn as an accent line
// across the bottom of the card. Errors light too, in the same way, because
// they are the other thing you came here to find. Everything else waits
// quietly under its series.
//
// Two menus become one Tide sheet each, and the pause/resume FAB becomes a
// floating bar — the same persistent-action shape the series screen uses.
// ===========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/download/download_repository.dart';
import '../tide/tide.dart';

/// Mihon's "Download queue" screen. Lists the currently-running download
/// (if any) followed by everything still queued, with per-row cancel and a
/// "Cancel all" action.
///
/// Progress is surfaced via the repository's broadcast event stream.
/// Structural events (enqueue / completion / pause / …) rebuild the
/// screen; per-page `downloading` ticks — several a second during a bulk
/// download — flow through per-chapter ValueNotifiers so only the running
/// row's progress area repaints, not the whole queue.
class DownloadQueueScreen extends ConsumerStatefulWidget {
  const DownloadQueueScreen({super.key});

  @override
  ConsumerState<DownloadQueueScreen> createState() =>
      _DownloadQueueScreenState();
}

class _DownloadQueueScreenState extends ConsumerState<DownloadQueueScreen> {
  StreamSubscription<DownloadEvent>? _sub;
  // ChapterId -> live progress/page-count payload for that row's tile.
  // Entries persist until the screen closes (bounded by the chapters seen
  // while open) so a notifier is never disposed under a listening builder.
  final Map<int, ValueNotifier<_TileProgress?>> _ticks = {};
  // ChapterIds we've seen a `downloading` event for — the first tick of a
  // chapter means it just went queued -> running (row pins to the top),
  // which IS a structural change worth one rebuild.
  final Set<int> _running = <int>{};

  /// Series headers the user has collapsed. Expanded is the default, so this
  /// holds the exceptions rather than the rule.
  final Set<int> _collapsed = <int>{};

  @override
  void initState() {
    super.initState();
    final repo = ref.read(downloadRepositoryProvider);
    _sub = repo.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final n in _ticks.values) {
      n.dispose();
    }
    super.dispose();
  }

  ValueNotifier<_TileProgress?> _tickFor(int chapterId) =>
      _ticks[chapterId] ??= ValueNotifier<_TileProgress?>(null);

  void _onEvent(DownloadEvent ev) {
    if (!mounted) return;
    switch (ev.state) {
      case DownloadState.downloading:
        final tick = _tickFor(ev.chapterId);
        final prev = tick.value;
        tick.value = _TileProgress(
          progress: ev.progress ?? prev?.progress,
          counts: (ev.downloadedPages != null && ev.totalPages != null)
              ? (ev.downloadedPages!, ev.totalPages!)
              : prev?.counts,
        );
        if (_running.add(ev.chapterId)) setState(() {});
      case DownloadState.completed:
      case DownloadState.failed:
      case DownloadState.deleted:
        _running.remove(ev.chapterId);
        _ticks[ev.chapterId]?.value = null;
        setState(() {});
      case DownloadState.queued:
      case DownloadState.queuePaused:
      case DownloadState.queueResumed:
      case DownloadState.networkWaiting:
        setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(downloadRepositoryProvider);
    final items = repo.snapshot();
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: TideRise(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TideHeader(
                    title: 'Download queue',
                    actions: [
                      if (items.isNotEmpty) ...[
                        TideIconButton(
                          icon: Icons.sort,
                          onTap: () => _openSort(repo),
                        ),
                        const SizedBox(width: 9),
                        TideIconButton(
                          icon: Icons.delete_sweep_outlined,
                          onTap: () => _confirmClearQueue(context, repo),
                        ),
                      ],
                    ],
                  ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Row(
                        children: [
                          Text(
                            items.length == 1
                                ? '1 chapter queued'
                                : '${items.length} chapters queued',
                            style:
                                TideText.caption(size: 12.5, opacity: 0.42),
                          ),
                        ],
                      ),
                    ),
                  if (repo.isPaused)
                    const _QueueBanner(
                      icon: Icons.pause_circle_outline,
                      text: 'Queue paused — the running chapter will finish, '
                          'but no further jobs will start.',
                    )
                  else if (repo.isWaitingForNetwork)
                    const _QueueBanner(
                      icon: Icons.wifi_off,
                      text: 'Waiting for an allowed network — downloads only '
                          'run over Wi-Fi while that setting is on.',
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? const _EmptyQueue()
                        : _list(repo, items),
                  ),
                ],
              ),
            ),
            if (items.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _PauseBar(
                  paused: repo.isPaused,
                  onTap: () {
                    if (repo.isPaused) {
                      repo.resumeQueue();
                    } else {
                      repo.pauseQueue();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Kotlin's Sort menu, as a sheet.
  Future<void> _openSort(DownloadRepository repo) async {
    final picked = await showTideSheet<String>(
      context,
      (_) => const TideOptionSheet(
        title: 'Sort queue',
        options: [
          ('dateNewest', 'Upload date · Newest'),
          ('dateOldest', 'Upload date · Oldest'),
          ('numberAsc', 'Chapter number · Ascending'),
          ('numberDesc', 'Chapter number · Descending'),
        ],
        // The queue has no persisted sort — each pick is a one-shot reorder,
        // so nothing is ever pre-selected.
        selected: '',
      ),
    );
    switch (picked) {
      case 'dateNewest':
        repo.sortQueue((a, b) => b.dateUpload.compareTo(a.dateUpload));
      case 'dateOldest':
        repo.sortQueue((a, b) => a.dateUpload.compareTo(b.dateUpload));
      case 'numberAsc':
        repo.sortQueue((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
      case 'numberDesc':
        repo.sortQueue((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
    }
  }

  Future<void> _confirmClearQueue(
    BuildContext context,
    DownloadRepository repo,
  ) async {
    final ok = await showTideSheet<bool>(
      context,
      (_) => const TideConfirmSheet(
        title: 'Clear download queue',
        message: 'Queued chapters will be removed. The currently downloading '
            'chapter will finish.',
        confirmLabel: 'Clear',
      ),
    );
    if (ok == true) {
      final removed = repo.clearQueue();
      if (!context.mounted) return;
      TideToast.of(context).show(
        removed == 1 ? 'Removed 1 chapter' : 'Removed $removed chapters',
      );
    }
  }

  Widget _list(DownloadRepository repo, List<ActiveDownload> items) {
    // Snapshot orders running, then errored, then queued. Pin the running
    // and errored rows at the top; the queued remainder renders grouped by
    // manga (Kotlin's DownloadHeaderItem: a collapsible series header with
    // its chapters beneath and series-level move-to-top / cancel actions —
    // replaces the old flat drag-to-reorder list; ordering is still
    // available via Sort + "Move series to top").
    final pinned =
        items.where((i) => i.current || i.errored).toList(growable: false);
    final queued =
        items.where((i) => !i.current && !i.errored).toList(growable: false);

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
      padding: EdgeInsets.fromLTRB(16, 8, 16, items.isEmpty ? 28 : 104),
      children: [
        for (final item in pinned) ...[
          _tile(repo, item),
          const SizedBox(height: 8),
        ],
        if (pinned.isNotEmpty && groupOrder.isNotEmpty)
          const TideSectionHeader(
            label: 'Waiting',
            padding: EdgeInsets.fromLTRB(4, 14, 4, 12),
          ),
        for (final mangaId in groupOrder) _group(repo, groups[mangaId]!),
      ],
    );
  }

  /// One manga's queued chapters under a collapsible series header.
  Widget _group(DownloadRepository repo, List<ActiveDownload> group) {
    final manga = group.first.manga;
    final n = group.length;
    final collapsed = _collapsed.contains(manga.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          TideRow(
            icon: collapsed ? Icons.chevron_right : Icons.expand_more,
            title: manga.title,
            subtitle: n == 1 ? '1 chapter' : '$n chapters',
            onTap: () => setState(() {
              if (!_collapsed.add(manga.id)) _collapsed.remove(manga.id);
            }),
            trailing: _RowAction(
              icon: Icons.more_horiz,
              onTap: () => _openGroupActions(repo, group),
            ),
          ),
          if (!collapsed)
            for (final item in group)
              Padding(
                // Indented under their series header, and led by the
                // chapter rather than the manga title.
                padding: const EdgeInsets.only(left: 22, top: 7),
                child: _tile(repo, item, inGroup: true),
              ),
        ],
      ),
    );
  }

  Future<void> _openGroupActions(
    DownloadRepository repo,
    List<ActiveDownload> group,
  ) async {
    final picked = await showTideSheet<String>(
      context,
      (_) => TideOptionSheet(
        title: group.first.manga.title,
        options: const [
          ('top', 'Move series to top'),
          ('cancel', 'Cancel all in series'),
        ],
        selected: '',
      ),
    );
    switch (picked) {
      case 'top':
        // Walk the group's chapters into the front of the queue, preserving
        // their relative order (Kotlin "Move series to top").
        for (final (i, item) in group.indexed) {
          repo.reorderQueue(item.chapter.id, i);
        }
      case 'cancel':
        for (final item in group) {
          repo.cancel(item.chapter.id);
        }
    }
  }

  Widget _tile(
    DownloadRepository repo,
    ActiveDownload item, {
    bool inGroup = false,
  }) {
    final chapterLabel = item.chapter.name.isEmpty
        ? 'Chapter ${item.chapter.chapterNumber}'
        : item.chapter.name;
    // The two rows worth finding at a glance: the one moving, and the one
    // that failed.
    final lit = item.current || item.errored;
    return TideGlass(
      radius: 16,
      tintTop: lit ? 0.13 : 0.06,
      tintBottom: lit ? 0.05 : 0.022,
      highlight: lit ? 0.20 : 0.12,
      border: lit ? 0.20 : 0.08,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
            child: Row(
              children: [
                Icon(
                  item.errored
                      ? Icons.error_outline
                      : item.current
                          ? Icons.downloading
                          : Icons.hourglass_empty,
                  size: 18,
                  color: item.errored
                      ? const Color(0xFFE8837F)
                      : item.current
                          ? TideColors.accent
                          : TideColors.textAt(0.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inGroup ? chapterLabel : item.manga.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TideText.title(size: inGroup ? 13.5 : 14.5),
                      ),
                      if (!inGroup) ...[
                        const SizedBox(height: 2),
                        Text(
                          chapterLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.caption(),
                        ),
                      ],
                      if (item.errored) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Download error',
                          style: TideText.caption(size: 11.5, opacity: 0.75)
                              .copyWith(color: const Color(0xFFE8837F)),
                        ),
                      ] else if (item.current)
                        _ProgressLabel(
                          tick: _tickFor(item.chapter.id),
                          item: item,
                        ),
                    ],
                  ),
                ),
                if (item.errored)
                  _RowAction(
                    icon: Icons.refresh,
                    onTap: () => repo.retry(item.chapter.id),
                  ),
                _RowAction(
                  icon: Icons.close_rounded,
                  onTap: () => repo.cancel(item.chapter.id),
                ),
              ],
            ),
          ),
          // Progress as a line across the foot of the card — the accent
          // doing the one job Nocturne gives it.
          if (item.current)
            _ProgressLine(tick: _tickFor(item.chapter.id), item: item),
        ],
      ),
    );
  }
}

/// The "x/y" page counter under a running row's title.
class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.tick, required this.item});

  final ValueNotifier<_TileProgress?> tick;
  final ActiveDownload item;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_TileProgress?>(
      valueListenable: tick,
      builder: (context, value, _) {
        // Prefer the live event count; fall back to the snapshot's counts so
        // a freshly opened screen still shows "x/y" before the next event.
        final counts = value?.counts ??
            (item.totalPages > 0
                ? (item.downloadedPages, item.totalPages)
                : null);
        if (counts == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${counts.$1} / ${counts.$2} pages',
            style: TideText.caption(size: 11.5, opacity: 0.5),
          ),
        );
      },
    );
  }
}

/// A 3px accent line across the bottom of a running row.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.tick, required this.item});

  final ValueNotifier<_TileProgress?> tick;
  final ActiveDownload item;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_TileProgress?>(
      valueListenable: tick,
      builder: (context, value, _) {
        final progress = value?.progress;
        return SizedBox(
          height: 3,
          child: progress == null
              // No progress reported yet: an indeterminate sliver rather
              // than a full bar claiming completion.
              ? const TideProgressBar(value: null, height: 3)
              : Row(
                  children: [
                    Expanded(
                      flex: (progress.clamp(0.0, 1.0) * 1000).round(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: TideColors.accent,
                          boxShadow: [
                            BoxShadow(
                              color: TideColors.accent.withValues(alpha: 0.8),
                              blurRadius: 9,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - progress.clamp(0.0, 1.0)) * 1000).round(),
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Small quiet control at the end of a row.
class _RowAction extends StatelessWidget {
  const _RowAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 38,
        child: Icon(icon, size: 16, color: TideColors.textAt(0.42)),
      ),
    );
  }
}

/// Live progress payload for one queue row, pushed through its
/// ValueNotifier by the screen's single event subscription. Either side
/// may lag the other (events don't always carry both), so each event
/// merges with the previous value.
class _TileProgress {
  const _TileProgress({this.progress, this.counts});

  /// Last reported 0..1 progress, null until the first progress-bearing
  /// event (renders as an indeterminate bar).
  final double? progress;

  /// (downloaded, total) page counts for the "x/y" label.
  final (int, int)? counts;
}

/// Pause / resume, as a persistent bar rather than a FAB — same shape the
/// series screen's Continue bar uses.
class _PauseBar extends StatelessWidget {
  const _PauseBar({required this.paused, required this.onTap});

  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TideGlass(
        radius: 30,
        blur: true,
        tintTop: 0.14,
        tintBottom: 0.05,
        highlight: 0.28,
        border: 0.16,
        saturation: 1.9,
        onTap: onTap,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 44,
            offset: const Offset(0, 18),
          ),
        ],
        padding: const EdgeInsets.fromLTRB(22, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUEUE',
                    style: TideText.kicker(
                      size: 10,
                      color: TideColors.textAt(0.5),
                    ).copyWith(letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    paused ? 'Paused' : 'Running',
                    style: TideText.title(size: 15)
                        .copyWith(color: TideColors.textBright),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TideColors.accent,
                boxShadow: [
                  BoxShadow(
                    color: TideColors.accent.withValues(alpha: 0.55),
                    blurRadius: 26,
                  ),
                ],
              ),
              child: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 22,
                color: const Color(0xFF12141F),
              ),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TideGlass(
        radius: 16,
        tintTop: 0.09,
        tintBottom: 0.03,
        highlight: 0.15,
        border: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: TideColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TideText.caption(size: 12.5, opacity: 0.6)
                    .copyWith(height: 1.45),
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No downloads', style: TideText.display(23)),
            const SizedBox(height: 10),
            Text(
              'Chapters you queue for offline reading appear here while they '
              'download.',
              textAlign: TextAlign.center,
              style: TideText.body(),
            ),
          ],
        ),
      ),
    );
  }
}
