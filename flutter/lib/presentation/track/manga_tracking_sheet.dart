import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/track/track_repository.dart';
import '../../data/track/tracker.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/track/model/track.dart';
import '../../domain/track/model/tracker.dart';
import '../tide/tide.dart';

/// Bottom sheet that lists every tracker for a given manga, surfacing the
/// current bound state and letting the user search + bind / unbind.
///
/// Drawn by long-pressing the "Tracking" button on the manga details
/// screen (matching Mihon's UX).
class MangaTrackingSheet extends ConsumerWidget {
  const MangaTrackingSheet({super.key, required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(trackerRegistryProvider);
    final repo = ref.watch(trackRepositoryProvider);
    return TideSheetPanel(
      child: StreamBuilder<List<Track>>(
        stream: repo.watchByMangaId(manga.id),
        builder: (context, snap) {
          final tracks = snap.data ?? const <Track>[];
          final byTrackerId = {for (final t in tracks) t.trackerId: t};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tracking', style: TideText.display(21)),
              const SizedBox(height: 6),
              Text(
                tracks.isEmpty
                    ? 'Not tracked anywhere'
                    : 'Tracked on ${tracks.length} '
                        '${tracks.length == 1 ? 'service' : 'services'}',
                style: TideText.caption(size: 13),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: registry.all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final tracker = registry.all[i];
                    return _TrackerRow(
                      manga: manga,
                      tracker: tracker,
                      track: byTrackerId[tracker.id],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackerRow extends ConsumerStatefulWidget {
  const _TrackerRow({
    required this.manga,
    required this.tracker,
    required this.track,
  });

  final Manga manga;
  final Tracker tracker;
  final Track? track;

  @override
  ConsumerState<_TrackerRow> createState() => _TrackerRowState();
}

class _TrackerRowState extends ConsumerState<_TrackerRow> {
  bool _working = false;

  Future<void> _searchAndBind() async {
    final loggedIn = await widget.tracker.isLoggedIn;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!loggedIn) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Log in to ${widget.tracker.name} from Settings → Trackers first.',
          ),
        ),
      );
      return;
    }
    final picked = await showTideSheet<TrackSearchResult>(
      context,
      (_) => _TrackerSearchSheet(
        tracker: widget.tracker,
        initialQuery: widget.manga.title,
      ),
    );
    if (picked == null) return;
    setState(() => _working = true);
    try {
      final track = await widget.tracker.bind(widget.manga.id, picked);
      await ref.read(trackRepositoryProvider).upsert(track);
      messenger.showSnackBar(
        SnackBar(content: Text('Bound to ${widget.tracker.name}.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Bind failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _unbind() async {
    await ref.read(trackRepositoryProvider).delete(
          mangaId: widget.manga.id,
          trackerId: widget.tracker.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final bound = track != null;
    return TideGlass(
      radius: 15,
      // A bound tracker is an ON state, so it takes the accent edge the rest
      // of the app gives anything that is live.
      tintTop: bound ? 0.125 : 0.06,
      tintBottom: bound ? 0.045 : 0.02,
      highlight: bound ? 0.19 : 0.12,
      border: bound ? 0.20 : 0.08,
      onTap: bound ? null : _searchAndBind,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bound
                  ? TideColors.accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: bound
                    ? TideColors.accent.withValues(alpha: 0.32)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Text(
              widget.tracker.name.substring(0, 1).toUpperCase(),
              style: TideText.title(
                size: 14,
                color: bound ? TideColors.accent : TideColors.textAt(0.7),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.tracker.name, style: TideText.title()),
                const SizedBox(height: 2),
                Text(
                  bound
                      ? '${widget.tracker.getStatusName(track.status)} · '
                          'Ch ${track.lastChapterRead.toInt()}'
                          '${track.totalChapters > 0 ? ' of ${track.totalChapters}' : ''}'
                      : widget.tracker.category == TrackerCategory.advanced
                          ? 'Advanced · tap to link'
                          : 'Tap to link',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.caption(),
                ),
                if (bound) ...[
                  const SizedBox(height: 2),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(size: 11, opacity: 0.32),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_working)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TideColors.accent,
              ),
            )
          else if (bound)
            TideIconButton(icon: Icons.link_off, onTap: _unbind)
          else
            TideIconButton(icon: Icons.add, onTap: _searchAndBind),
        ],
      ),
    );
  }
}

class _TrackerSearchSheet extends StatefulWidget {
  const _TrackerSearchSheet({
    required this.tracker,
    required this.initialQuery,
  });

  final Tracker tracker;
  final String initialQuery;

  @override
  State<_TrackerSearchSheet> createState() => _TrackerSearchSheetState();
}

class _TrackerSearchSheetState extends State<_TrackerSearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  List<TrackSearchResult>? _results;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.tracker.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search ${widget.tracker.name}',
                style: TideText.display(20)),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: TideGlass(
                radius: 22,
                tintTop: 0.09,
                tintBottom: 0.03,
                highlight: 0.16,
                border: 0.11,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search,
                        size: 17, color: TideColors.textAt(0.45)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        cursorColor: TideColors.accent,
                        style: TideText.title(size: 14.5),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Title',
                          hintStyle: TideText.title(
                            size: 14.5,
                            color: TideColors.textAt(0.33),
                          ),
                        ),
                        onSubmitted: (_) => _runSearch(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: TideColors.accent,
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Text('Search failed: $error',
            textAlign: TextAlign.center, style: TideText.body()),
      );
    }
    final results = _results;
    if (results == null || results.isEmpty) {
      return Center(child: Text('No matches.', style: TideText.body()));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = results[i];
        final facts = [
          if (r.publishingStatus != null) r.publishingStatus!,
          if (r.publishingType != null) r.publishingType!,
          if (r.totalChapters > 0) '${r.totalChapters} ch',
        ].join(' · ');
        return TideGlass(
          radius: 14,
          tintTop: 0.085,
          tintBottom: 0.03,
          highlight: 0.15,
          border: 0.10,
          onTap: () => Navigator.of(context).pop(r),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TideText.title(size: 14),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(facts, style: TideText.caption(size: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}
