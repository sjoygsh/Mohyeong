import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/browse_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/source_id.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_manga.dart';
import '../cloudflare/cloudflare_solver_screen.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

/// URLs of the manga already favourited for a given source id. Used to
/// drop in-library results from the browse grid when the
/// `hideInLibraryItems` preference is on.
final favoritedUrlsForSourceProvider =
    FutureProvider.family<Set<String>, int>((ref, sourceId) async {
  final repo = ref.watch(mangaRepositoryProvider);
  final favorites = await repo.getFavoritesBySource(sourceId);
  return favorites.map((m) => m.url).toSet();
});

/// Browses a single installed source: tabs for Popular / Latest / Search,
/// each backed by an infinite-scroll grid pulled from the JS extension.
class SourceBrowseScreen extends ConsumerStatefulWidget {
  const SourceBrowseScreen({
    super.key,
    required this.sourceId,
    this.initialQuery,
  });

  final String sourceId;

  /// When non-null/non-empty the screen opens on the Search tab with this
  /// query pre-run — used by Global search's "open source" affordance,
  /// mirroring Kotlin handing the query to BrowseSourceScreen.
  final String? initialQuery;

  @override
  ConsumerState<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends ConsumerState<SourceBrowseScreen> {
  Future<MangaSource>? _sourceFuture;

  @override
  void initState() {
    super.initState();
    _sourceFuture = ref.read(extensionRepositoryProvider)
        .getSource(widget.sourceId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MangaSource>(
      future: _sourceFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Failed to load source: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final source = snap.data!;
        final tabs = <Tab>[
          const Tab(text: 'Popular'),
          if (source.supportsLatest) const Tab(text: 'Latest'),
          const Tab(text: 'Search'),
        ];
        final hasInitialQuery =
            widget.initialQuery != null && widget.initialQuery!.isNotEmpty;
        return DefaultTabController(
          length: tabs.length,
          // Search is always the last tab; land on it when pre-filled.
          initialIndex: hasInitialQuery ? tabs.length - 1 : 0,
          child: Scaffold(
            appBar: AppBar(
              title: Text(source.name),
              actions: [
                // Kotlin BrowseSourceToolbar's "Display mode" selector.
                Consumer(
                  builder: (context, ref, _) {
                    final current = SourceDisplayMode.fromName(
                      ref.watch(sourceDisplayModeProvider),
                    );
                    return PopupMenuButton<SourceDisplayMode>(
                      tooltip: 'Display mode',
                      icon: const Icon(Icons.view_module_outlined),
                      onSelected: (mode) => ref
                          .read(sourceDisplayModeProvider.notifier)
                          .set(mode.storageName),
                      itemBuilder: (_) => [
                        for (final mode in SourceDisplayMode.values)
                          CheckedPopupMenuItem(
                            value: mode,
                            checked: mode == current,
                            child: Text(mode.label),
                          ),
                      ],
                    );
                  },
                ),
                if (source.baseUrl.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.shield_outlined),
                    tooltip: 'Solve Cloudflare challenge',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CloudflareSolverScreen(url: source.baseUrl),
                        ),
                      );
                    },
                  ),
              ],
              bottom: TabBar(tabs: tabs),
            ),
            body: TabBarView(
              children: [
                _Listing(source: source, mode: _ListingMode.popular),
                if (source.supportsLatest)
                  _Listing(source: source, mode: _ListingMode.latest),
                _SearchListing(
                  source: source,
                  initialQuery: widget.initialQuery,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ListingMode { popular, latest }

class _Listing extends StatefulWidget {
  const _Listing({required this.source, required this.mode});

  final MangaSource source;
  final _ListingMode mode;

  @override
  State<_Listing> createState() => _ListingState();
}

class _ListingState extends State<_Listing>
    with AutomaticKeepAliveClientMixin<_Listing> {
  final List<SourceManga> _items = [];
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = widget.mode == _ListingMode.popular
          ? await widget.source.fetchPopular(_page)
          : await widget.source.fetchLatest(_page);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.mangas);
        _hasNext = page.hasNextPage;
        if (_hasNext) _page++;
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
  Widget build(BuildContext context) {
    super.build(context);
    return _MangaGrid(
      items: _items,
      sourceId: widget.source.id,
      loading: _loading,
      error: _error,
      hasMore: _hasNext,
      onLoadMore: _loadMore,
    );
  }
}

class _SearchListing extends StatefulWidget {
  const _SearchListing({required this.source, this.initialQuery});

  final MangaSource source;
  final String? initialQuery;

  @override
  State<_SearchListing> createState() => _SearchListingState();
}

class _SearchListingState extends State<_SearchListing>
    with AutomaticKeepAliveClientMixin<_SearchListing> {
  final TextEditingController _controller = TextEditingController();
  final List<SourceManga> _items = [];
  String _query = '';
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      _search(initial);
    }
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _items.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext || _query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final page = await widget.source.fetchSearch(_query, _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.mangas);
        _hasNext = page.hasNextPage;
        if (_hasNext) _page++;
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
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search this source',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (q) => _search(q.trim()),
          ),
        ),
        if (_query.isEmpty)
          const Expanded(
            child: Center(child: Text('Enter a query to search.')),
          )
        else
          Expanded(
            child: _MangaGrid(
              items: _items,
              sourceId: widget.source.id,
              loading: _loading,
              error: _error,
              hasMore: _hasNext,
              onLoadMore: _loadMore,
            ),
          ),
      ],
    );
  }
}

class _MangaGrid extends ConsumerWidget {
  const _MangaGrid({
    required this.items,
    required this.sourceId,
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<SourceManga> items;
  final String sourceId;
  final bool loading;
  final Object? error;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideInLibrary = ref.watch(hideInLibraryItemsProvider);
    final sourceIdInt = sourceNumericId(sourceId);
    List<SourceManga> items = this.items;
    if (hideInLibrary) {
      final favoritedUrls = ref
          .watch(favoritedUrlsForSourceProvider(sourceIdInt))
          .valueOrNull;
      if (favoritedUrls != null) {
        items = items
            .where((m) => !favoritedUrls.contains(m.url))
            .toList(growable: false);
      }
    }
    if (error != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load: $error'),
        ),
      );
    }
    if (items.isEmpty && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const Center(child: Text('No results found'));
    }
    // Kotlin sourceDisplayMode: compact grid (title over cover),
    // comfortable grid (title under cover), or list rows.
    final mode =
        SourceDisplayMode.fromName(ref.watch(sourceDisplayModeProvider));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !loading &&
            hasMore) {
          onLoadMore();
        }
        return false;
      },
      child: mode == SourceDisplayMode.list
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _MangaCard(
                  manga: items[i],
                  sourceId: sourceId,
                  style: mode,
                );
              },
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                // Comfortable cells are taller to fit the caption row.
                childAspectRatio:
                    mode == SourceDisplayMode.comfortableGrid ? 0.52 : 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _MangaCard(
                  manga: items[i],
                  sourceId: sourceId,
                  style: mode,
                );
              },
            ),
    );
  }
}

class _MangaCard extends ConsumerWidget {
  const _MangaCard({
    required this.manga,
    required this.sourceId,
    this.style = SourceDisplayMode.compactGrid,
  });

  final SourceManga manga;
  final String sourceId;

  /// Which of the three Kotlin display modes to render as.
  final SourceDisplayMode style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    final sourceIdInt = sourceNumericId(sourceId);
    final favoritedUrls = ref
            .watch(favoritedUrlsForSourceProvider(sourceIdInt))
            .valueOrNull ??
        const <String>{};
    final inLibrary = favoritedUrls.contains(manga.url);

    // Mirrors Mihon: covers already in the library are dimmed.
    final coverImage = Opacity(
      opacity: inLibrary ? 0.34 : 1,
      child: (url == null || url.isEmpty)
          ? Container(color: placeholder)
          : SourceImage(
              url: url,
              fit: BoxFit.cover,
              placeholder: (_) => Container(color: placeholder),
              errorWidget: (_, _) => Container(color: placeholder),
            ),
    );

    // Tap routes via `insertFromSource` (resolves an existing row when
    // (url, source) already matches, inserts a non-favourite row otherwise)
    // into the manga details screen — same flow Mihon uses to open a source
    // manga before it's added to the library. Long-press toggles library
    // membership in place (Mihon's long-press add/remove).
    void onTap() => _openManga(context, ref);
    void onLongPress() =>
        _toggleFavorite(context, ref, sourceIdInt, inLibrary);

    if (style == SourceDisplayMode.list) {
      return ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 40, height: 56, child: coverImage),
        ),
        title: Text(
          manga.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: inLibrary ? const _InLibraryChip() : null,
        onTap: onTap,
        onLongPress: onLongPress,
      );
    }

    final coverStack = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          coverImage,
          // Compact grid draws the title over the cover bottom; the
          // comfortable grid keeps the cover clean and captions below.
          if (style == SourceDisplayMode.compactGrid) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ],
          if (inLibrary) const _InLibraryBadge(),
          if (style == SourceDisplayMode.compactGrid)
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
              ),
            ),
          ),
        ],
      ),
    );

    if (style == SourceDisplayMode.comfortableGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: coverStack),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
    }
    return coverStack;
  }

  Future<void> _openManga(BuildContext context, WidgetRef ref) async {
    final sourceIdInt = sourceNumericId(sourceId);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final inserted = await ref
          .read(mangaRepositoryProvider)
          .insertFromSource(candidate: manga, sourceId: sourceIdInt);
      if (!context.mounted) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(mangaId: inserted.id),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open manga: $e')),
      );
    }
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    int sourceIdInt,
    bool inLibrary,
  ) async {
    final repo = ref.read(mangaRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (inLibrary) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text('Remove "${manga.title}" from your library?'),
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
      );
      if (confirmed != true) return;
    }
    try {
      final row =
          await repo.insertFromSource(candidate: manga, sourceId: sourceIdInt);
      await repo.setFavorite(row.id, !inLibrary);
      ref.invalidate(favoritedUrlsForSourceProvider(sourceIdInt));
      messenger.showSnackBar(
        SnackBar(
          content: Text(inLibrary ? 'Removed from library' : 'Added to library'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update library: $e')),
      );
    }
  }
}

/// Small "in library" indicator overlaid on a source cover's top-left,
/// mirroring Mihon's MangaCover in-library badge.
/// Trailing "In library" marker for list-mode rows (the grid corner badge
/// doesn't fit a ListTile).
class _InLibraryChip extends StatelessWidget {
  const _InLibraryChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'In library',
        style: TextStyle(fontSize: 11, color: scheme.onSecondary),
      ),
    );
  }
}

class _InLibraryBadge extends StatelessWidget {
  const _InLibraryBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.secondary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
        ),
        child: Icon(
          Icons.collections_bookmark,
          size: 14,
          color: scheme.onSecondary,
        ),
      ),
    );
  }
}
