// ===========================================================================
// Tide source browse.
//
// A catalogue is artwork, so the covers carry the screen and everything else
// gets out of their way: no app bar, no tab underline, no chrome that isn't a
// control. Popular / Latest / Search sit behind the same glass segmented
// control Browse uses, and the source's own filters open as a Tide sheet.
//
// The three Kotlin display modes survive intact — compact grid (title over the
// cover), comfortable grid (title beneath it), and list — because which one
// you want depends on whether you are recognising covers or reading titles.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/browse_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/source_id.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_manga.dart';
import '../cloudflare/cloudflare_solver_screen.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';
import '../tide/tide.dart';

/// URLs of the manga already favourited for a given source id. Used to
/// drop in-library results from the browse grid when the
/// `hideInLibraryItems` preference is on.
final favoritedUrlsForSourceProvider =
    FutureProvider.family<Set<String>, int>((ref, sourceId) async {
  final repo = ref.watch(mangaRepositoryProvider);
  final favorites = await repo.getFavoritesBySource(sourceId);
  return favorites.map((m) => m.url).toSet();
});

/// Browses a single installed source: Popular / Latest / Search, each backed
/// by an infinite-scroll grid pulled from the JS extension.
class SourceBrowseScreen extends ConsumerStatefulWidget {
  const SourceBrowseScreen({
    super.key,
    required this.sourceId,
    this.initialQuery,
  });

  final String sourceId;

  /// When non-null/non-empty the screen opens on the Search view with this
  /// query pre-run — used by Global search's "open source" affordance,
  /// mirroring Kotlin handing the query to BrowseSourceScreen.
  final String? initialQuery;

  @override
  ConsumerState<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends ConsumerState<SourceBrowseScreen> {
  Future<MangaSource>? _sourceFuture;
  int? _view;

  /// Views already visited. The current one always builds; these keep their
  /// loaded pages and scroll position after you switch away.
  ///
  /// Load-bearing: every view fetches on its first build — Popular and Latest
  /// each pull a page, and Search asks the extension for its filter list — so
  /// building all three up front would fire three requests at a source the
  /// moment you opened it, for two results nobody asked to see.
  final Set<int> _built = {};

  @override
  void initState() {
    super.initState();
    _sourceFuture =
        ref.read(extensionRepositoryProvider).getSource(widget.sourceId);
  }

  bool get _hasInitialQuery =>
      widget.initialQuery != null && widget.initialQuery!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: FutureBuilder<MangaSource>(
        future: _sourceFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Chrome(
              title: 'Source',
              child: _Note('Failed to load source: ${snap.error}'),
            );
          }
          if (!snap.hasData) {
            return const _Chrome(title: 'Source', child: _Spinner());
          }
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(MangaSource source) {
    final labels = <String>[
      'Popular',
      if (source.supportsLatest) 'Latest',
      'Search',
    ];
    // Search is always the last view; land on it when pre-filled.
    final view = _view ??= _hasInitialQuery ? labels.length - 1 : 0;
    final searchIndex = labels.length - 1;

    return _Chrome(
      title: source.name,
      actions: [
        const _DisplayModeButton(),
        if (source.baseUrl.isNotEmpty) ...[
          const SizedBox(width: 9),
          TideIconButton(
            icon: Icons.shield_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CloudflareSolverScreen(url: source.baseUrl),
              ),
            ),
          ),
        ],
      ],
      segmented: TideSegmented(
        labels: labels,
        index: view,
        onChanged: (i) => setState(() {
          // The one being left joins the built set so it survives the switch.
          _built.add(view);
          _view = i;
        }),
      ),
      child: IndexedStack(
        index: view,
        children: [
          for (var i = 0; i < labels.length; i++)
            if (i == view || _built.contains(i))
              _viewAt(i, source, searchIndex, view)
            else
              const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _viewAt(int i, MangaSource source, int searchIndex, int view) {
    if (i == searchIndex) {
      return _SearchListing(
        source: source,
        initialQuery: widget.initialQuery,
        active: view == searchIndex,
      );
    }
    return _Listing(
      source: source,
      mode: i == 0 ? _ListingMode.popular : _ListingMode.latest,
    );
  }
}

/// Header, segmented control and body — the frame every state of this screen
/// renders inside, so a failure still has a way back.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.title,
    required this.child,
    this.actions = const [],
    this.segmented,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? segmented;

  @override
  Widget build(BuildContext context) {
    return TideRise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12,
              20,
              12,
            ),
            child: Row(
              children: [
                TideIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 15,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                      color: TideColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ...actions,
              ],
            ),
          ),
          if (segmented != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: segmented!,
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Kotlin BrowseSourceToolbar's display-mode selector, as a sheet rather than
/// a popup menu — a Material menu here would be the only opaque slab on the
/// screen.
class _DisplayModeButton extends ConsumerWidget {
  const _DisplayModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        SourceDisplayMode.fromName(ref.watch(sourceDisplayModeProvider));
    return TideIconButton(
      icon: Icons.view_module_outlined,
      onTap: () => showTideSheet<void>(
        context,
        (ctx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, mode) in SourceDisplayMode.values.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  TideRow(
                    icon: switch (mode) {
                      SourceDisplayMode.list => Icons.view_list_outlined,
                      SourceDisplayMode.comfortableGrid =>
                        Icons.view_comfy_alt_outlined,
                      _ => Icons.grid_view_outlined,
                    },
                    title: mode.label,
                    lit: mode == current,
                    trailing: mode == current
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: TideColors.accent)
                        : null,
                    onTap: () {
                      ref
                          .read(sourceDisplayModeProvider.notifier)
                          .set(mode.storageName);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
  const _SearchListing({
    required this.source,
    required this.active,
    this.initialQuery,
  });

  final MangaSource source;
  final String? initialQuery;

  /// Whether Search is the view on screen. The field only takes focus when it
  /// is — an autofocus inside an IndexedStack would raise the keyboard while
  /// the reader is looking at Popular.
  final bool active;

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

  // Source-declared search filters (optional JS `filters()` contract —
  // Kotlin's getFilterList) and the user's current picks. Selections only
  // hold NON-default values so an untouched sheet sends nothing.
  List<SourceFilterDef> _filterDefs = const [];
  final Map<String, String> _selections = {};
  bool _searchedOnce = false;

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
    widget.source.getFilters().then((defs) {
      if (mounted && defs.isNotEmpty) setState(() => _filterDefs = defs);
    }).catchError((_) {});
  }

  /// Bumped on every new search; an in-flight fetch that comes back with a
  /// stale generation is discarded. Without this, re-searching while a page
  /// was loading (a) bailed on the `_loading` guard so the NEW query never
  /// fetched, and (b) let the OLD query's response append into the freshly
  /// cleared list.
  int _generation = 0;

  Future<void> _search(String query) async {
    _generation++;
    setState(() {
      _query = query;
      _searchedOnce = true;
      _items.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
      // Any in-flight fetch belongs to the old generation now — release the
      // flag so THIS search's first page can start immediately.
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    // Filter-only browsing is allowed (empty query + active filters),
    // matching Kotlin's filter-driven search.
    if (_loading || !_hasNext || (_query.isEmpty && _selections.isEmpty)) {
      return;
    }
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await widget.source.fetchSearch(
        _query,
        _page,
        filters: _selections.isEmpty ? null : Map.of(_selections),
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.mangas);
        _hasNext = page.hasNextPage;
        if (_hasNext) _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Kotlin's source filter sheet: one control per declared filter, with
  /// Reset / Filter actions. Applying re-runs the search with the picks.
  void _openFilterSheet() {
    showTideSheet<void>(
      context,
      (ctx) => _SourceFilterSheet(
        defs: _filterDefs,
        initial: Map.of(_selections),
        onApply: (picks) {
          _selections
            ..clear()
            ..addAll(picks);
          _search(_controller.text.trim());
        },
      ),
    );
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TideGlass(
                    radius: 21,
                    tintTop: 0.09,
                    tintBottom: 0.03,
                    highlight: 0.16,
                    border: 0.11,
                    padding: const EdgeInsets.only(left: 15, right: 12),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            size: 17, color: TideColors.textAt(0.42)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: widget.active && !_searchedOnce,
                            cursorColor: TideColors.accent,
                            style: TideText.title(size: 14.5),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (q) => _search(q.trim()),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              hintText: 'Search this source',
                              hintStyle: TideText.title(
                                size: 14.5,
                                color: TideColors.textAt(0.33),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_filterDefs.isNotEmpty) ...[
                const SizedBox(width: 9),
                TideIconButton(
                  icon: Icons.filter_list,
                  size: 42,
                  onTap: _openFilterSheet,
                ),
              ],
            ],
          ),
        ),
        if (!_searchedOnce)
          Expanded(
            child: _Note(
              _filterDefs.isEmpty
                  ? 'Enter a query to search.'
                  : 'Enter a query or apply filters to search.',
            ),
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

/// Sheet rendering a source's declared search filters: `select` filters as
/// chip rows, `checkbox` filters as Tide checks. Only non-default picks are
/// reported, so Reset genuinely clears the search.
class _SourceFilterSheet extends StatefulWidget {
  const _SourceFilterSheet({
    required this.defs,
    required this.initial,
    required this.onApply,
  });

  final List<SourceFilterDef> defs;
  final Map<String, String> initial;
  final ValueChanged<Map<String, String>> onApply;

  @override
  State<_SourceFilterSheet> createState() => _SourceFilterSheetState();
}

class _SourceFilterSheetState extends State<_SourceFilterSheet> {
  late final Map<String, String> _draft = Map.of(widget.initial);

  String _effective(SourceFilterDef def) =>
      _draft[def.key] ?? def.defaultValue ?? '';

  void _set(SourceFilterDef def, String value) {
    setState(() {
      if (value == (def.defaultValue ?? '')) {
        _draft.remove(def.key);
      } else {
        _draft[def.key] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: TideGlass(
          radius: 26,
          blur: true,
          tintTop: 0.13,
          tintBottom: 0.05,
          highlight: 0.26,
          border: 0.15,
          saturation: 1.9,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filters', style: TideText.display(21)),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final def in widget.defs) ...[
                        const SizedBox(height: 16),
                        if (def.type == 'checkbox')
                          TideCheck(
                            label: def.title,
                            value: _effective(def) == 'true',
                            onChanged: (v) => _set(def, v ? 'true' : ''),
                          )
                        else ...[
                          Text(
                            def.title.toUpperCase(),
                            style: TideText.kicker(size: 10.5)
                                .copyWith(letterSpacing: 1.6),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final opt in def.options)
                                TideChip(
                                  label: opt.label,
                                  selected: _effective(def) == opt.value,
                                  onTap: () => _set(def, opt.value),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: TideGlass(
                        radius: 23,
                        tintTop: 0.09,
                        tintBottom: 0.03,
                        highlight: 0.16,
                        border: 0.11,
                        onTap: () => setState(_draft.clear),
                        child: Center(
                          child: Text(
                            'Reset',
                            style: TideText.title(
                              size: 14.5,
                              color: TideColors.textAt(0.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onApply(_draft);
                      },
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: TideColors.accent,
                          borderRadius: BorderRadius.circular(23),
                          boxShadow: [
                            BoxShadow(
                              color: TideColors.accent.withValues(alpha: 0.45),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Text(
                          'Filter',
                          style: TideText.title(size: 14.5)
                              .copyWith(color: TideColors.ground),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    List<SourceManga> items = this.items;
    if (hideInLibrary) {
      // Only needed for the favorites lookup below; computing it up front ran
      // sourceNumericId (an MD5 for non-numeric slugs) on every rebuild even
      // when the pref is off — the default.
      final sourceIdInt = sourceNumericId(sourceId);
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
      return _Note('Failed to load: $error');
    }
    if (items.isEmpty && loading) return const _Spinner();
    if (items.isEmpty) {
      // Local source empty state carries the guide link (Kotlin
      // BrowseSourceScreen's EmptyScreen action for LocalSource).
      if (sourceId == '0') {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No results found', style: TideText.body()),
              const SizedBox(height: 14),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => launchUrl(
                  Uri.parse(
                    'https://sjoygsh.github.io/Mohyeong/help.html#local-source',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Local source guide',
                  style: TideText.title(size: 13.5, color: TideColors.accent),
                ),
              ),
            ],
          ),
        );
      }
      return const _Note('No results found');
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
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= items.length) return const _TailSpinner();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _MangaCard(
                    manga: items[i],
                    sourceId: sourceId,
                    style: mode,
                  ),
                );
              },
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                // Comfortable cells are taller to fit the caption row.
                childAspectRatio:
                    mode == SourceDisplayMode.comfortableGrid ? 0.52 : 0.66,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= items.length) return const _TailSpinner();
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
    final url = manga.thumbnailUrl;
    final sourceIdInt = sourceNumericId(sourceId);
    // Source's image-request headers (Referer/UA) so hotlink-protected cover
    // CDNs don't 403 into a blank tile.
    final imageHeaders = ref
        .watch(installedSourceImageHeadersProvider)
        .valueOrNull?[sourceIdInt];
    final favoritedUrls = ref
            .watch(favoritedUrlsForSourceProvider(sourceIdInt))
            .valueOrNull ??
        const <String>{};
    final inLibrary = favoritedUrls.contains(manga.url);

    // A missing cover falls back to Tide's deterministic gradient rather than
    // a flat grey box: in a grid of artwork an empty cell reads as a hole.
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: TideCover.fallbackGradient(manga.url.hashCode),
      ),
    );
    // Mirrors Mihon: covers already in the library are dimmed. The dim rides
    // the image paint (Image.opacity) instead of an Opacity widget, which
    // saveLayered every dimmed cell each scrolled frame.
    final coverImage = (url == null || url.isEmpty)
        ? fallback
        : SourceImage(
            cacheWidth: 480,
            url: url,
            headers: imageHeaders,
            fit: BoxFit.cover,
            opacity:
                inLibrary ? const AlwaysStoppedAnimation<double>(0.34) : null,
            placeholder: (_) => fallback,
            errorWidget: (_, _) => fallback,
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
      return TideGlass(
        radius: 16,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: onLongPress,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 58,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: coverImage,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(),
                ),
              ),
              if (inLibrary) ...[
                const SizedBox(width: 10),
                const TideLibraryMark(),
              ],
            ],
          ),
        ),
      );
    }

    final coverStack = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverImage,
            // Compact draws the title over the cover, so it needs the scrim
            // the whole design uses under type on artwork; comfortable keeps
            // the cover clean and captions below.
            if (style == SourceDisplayMode.compactGrid) ...[
              const Positioned.fill(child: TideScrim()),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(size: 12.5).copyWith(
                    color: TideColors.brightAt(0.92),
                    height: 1.2,
                  ),
                ),
              ),
            ],
            if (inLibrary)
              const Positioned(top: 7, left: 7, child: TideLibraryMark()),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                onLongPress: onLongPress,
              ),
            ),
          ],
        ),
      ),
    );

    if (style == SourceDisplayMode.comfortableGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: coverStack),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TideText.caption(size: 11.5, opacity: 0.62),
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
      final confirmed = await showTideSheet<bool>(
        context,
        (_) => TideConfirmSheet(
          title: 'Remove from library',
          message: 'Remove "${manga.title}" from your library?',
          confirmLabel: 'Remove',
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
          content:
              Text(inLibrary ? 'Removed from library' : 'Added to library'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update library: $e')),
      );
    }
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: TideColors.accent),
      );
}

/// The load-more indicator that sits in the last grid cell / list row.
class _TailSpinner extends StatelessWidget {
  const _TailSpinner();

  @override
  Widget build(BuildContext context) => const Center(
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
