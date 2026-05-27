import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/track/track_repository.dart';
import '../../data/track/tracker.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/track/model/track.dart';
import '../../domain/track/model/tracker.dart';

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
    return SafeArea(
      child: StreamBuilder<List<Track>>(
        stream: repo.watchByMangaId(manga.id),
        builder: (context, snap) {
          final tracks = snap.data ?? const <Track>[];
          final byTrackerId = {for (final t in tracks) t.trackerId: t};
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'Tracking',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final tracker in registry.all)
                _TrackerRow(
                  manga: manga,
                  tracker: tracker,
                  track: byTrackerId[tracker.id],
                ),
              const SizedBox(height: 8),
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
    final picked = await showModalBottomSheet<TrackSearchResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrackerSearchSheet(
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
    return ListTile(
      leading: CircleAvatar(child: Text(widget.tracker.name.substring(0, 1))),
      title: Text(widget.tracker.name),
      subtitle: track == null
          ? Text(
              widget.tracker.category == TrackerCategory.advanced
                  ? 'Advanced — not bound'
                  : 'Not bound',
            )
          : Text(
              '${track.title} • '
              '${widget.tracker.getStatusName(track.status)} • '
              'Ch ${track.lastChapterRead.toInt()}'
              '${track.totalChapters > 0 ? '/${track.totalChapters}' : ''}',
            ),
      trailing: _working
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (track == null
              ? IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _searchAndBind,
                )
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Unbind',
                  onPressed: _unbind,
                )),
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search ${widget.tracker.name}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          Expanded(
            child: _buildBody(scrollController),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Search failed: $error')),
      );
    }
    final results = _results;
    if (results == null || results.isEmpty) {
      return const Center(child: Text('No matches.'));
    }
    return ListView.separated(
      controller: controller,
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 0),
      itemBuilder: (_, i) {
        final r = results[i];
        return ListTile(
          title: Text(r.title),
          subtitle: Text([
            if (r.publishingStatus != null) r.publishingStatus!,
            if (r.publishingType != null) r.publishingType!,
            if (r.totalChapters > 0) '${r.totalChapters} ch',
          ].join(' • ')),
          onTap: () => Navigator.of(context).pop(r),
        );
      },
    );
  }
}
