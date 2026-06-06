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
  const SourceBrowseScreen({super.key, required this.sourceId});

  final String sourceId;

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
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(source.name),
              actions: [
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
                _SearchListing(source: source),
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
  const _SearchListing({required this.source});

  final MangaSource source;

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
      return const Center(child: Text('No results.'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !loading &&
            hasMore) {
          onLoadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _MangaCard(manga: items[i], sourceId: sourceId);
        },
      ),
    );
  }
}

class _MangaCard extends ConsumerWidget {
  const _MangaCard({required this.manga, required this.sourceId});

  final SourceManga manga;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null || url.isEmpty)
            Container(color: placeholder)
          else
            SourceImage(
              url: url,
              fit: BoxFit.cover,
              placeholder: (_) => Container(color: placeholder),
              errorWidget: (_, _) => Container(color: placeholder),
            ),
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
          // Tap routes via `insertFromSource` (resolves an existing row
          // when (url, source) already matches, inserts a non-favourite
          // row otherwise) into the manga details screen — same flow
          // Mihon uses to open a source manga before it's added to the
          // library.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openManga(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
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
}
