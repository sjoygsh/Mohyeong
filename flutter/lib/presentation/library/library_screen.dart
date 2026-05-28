import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_updater.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/category/model/category.dart';
import '../../domain/library/model/library_item.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

/// Tri-state filters for the library grid. Each axis can be off (show
/// everything), include-only (show rows where the predicate matches),
/// or exclude (show rows where it doesn't). Mirrors Mihon's library
/// filter sheet — minus the Downloaded / Tracked axes, which need
/// per-row async lookups that aren't wired through this widget yet.
class LibraryFilters {
  const LibraryFilters({
    this.unread = TriState.disabled,
    this.started = TriState.disabled,
    this.bookmarked = TriState.disabled,
    this.completed = TriState.disabled,
  });

  final TriState unread;
  final TriState started;
  final TriState bookmarked;
  final TriState completed;

  bool get isActive =>
      unread != TriState.disabled ||
      started != TriState.disabled ||
      bookmarked != TriState.disabled ||
      completed != TriState.disabled;

  /// Mihon stores publication status as ints; `2` is "Completed".
  static const int _statusCompleted = 2;

  bool matches(LibraryItem item) {
    if (!applyTriState(unread, () => item.unreadCount > 0)) return false;
    if (!applyTriState(started, () => item.readCount > 0)) return false;
    if (!applyTriState(bookmarked, () => item.bookmarkCount > 0)) return false;
    if (!applyTriState(
        completed, () => item.manga.status == _statusCompleted)) {
      return false;
    }
    return true;
  }

  LibraryFilters copyWith({
    TriState? unread,
    TriState? started,
    TriState? bookmarked,
    TriState? completed,
  }) {
    return LibraryFilters(
      unread: unread ?? this.unread,
      started: started ?? this.started,
      bookmarked: bookmarked ?? this.bookmarked,
      completed: completed ?? this.completed,
    );
  }
}

/// Library tab: streams the favorites + per-manga aggregate stats from
/// `libraryView`, partitions by category (tabs above the grid when more
/// than one category exists), and renders one of three display modes:
///
/// * Comfortable — cover with title under the cover (default)
/// * Compact     — cover with title overlaid on the cover
/// * Cover only  — no title, denser grid
///
/// Each grid item carries an unread-count badge in the top-start corner,
/// matching Mihon's library presentation.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  LibraryFilters _filters = const LibraryFilters();
  bool _searching = false;
  bool _updating = false;
  int _selectedCategoryId = Category.uncategorizedId;
  // Manga ids the user has multi-selected via long-press. Empty set
  // means selection mode is off. Mihon shows a contextual app bar with
  // bulk actions when at least one item is selected.
  final Set<int> _selected = <int>{};
  late final TextEditingController _searchController =
      TextEditingController();

  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelected(int mangaId) {
    setState(() {
      if (_selected.contains(mangaId)) {
        _selected.remove(mangaId);
      } else {
        _selected.add(mangaId);
      }
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(() => _selected.clear());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Contextual app bar shown while at least one card is selected.
  /// Mirrors Mihon's library selection bar: back-arrow to dismiss,
  /// count title, mark-read, mark-unread, move-to-category, delete.
  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length}'),
      actions: [
        IconButton(
          icon: const Icon(Icons.done_all),
          tooltip: 'Mark as read',
          onPressed: () => _selectionMarkRead(true),
        ),
        IconButton(
          icon: const Icon(Icons.remove_done),
          tooltip: 'Mark as unread',
          onPressed: () => _selectionMarkRead(false),
        ),
        IconButton(
          icon: const Icon(Icons.label_outline),
          tooltip: 'Move to category',
          onPressed: _selectionMoveToCategory,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove from library',
          onPressed: _selectionRemoveFromLibrary,
        ),
      ],
    );
  }

  Future<void> _selectionMarkRead(bool read) async {
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final ids = _selected.toList(growable: false);
    for (final id in ids) {
      await chapterRepo.setReadForManga(id, read);
    }
    if (!mounted) return;
    _clearSelection();
  }

  Future<void> _selectionRemoveFromLibrary() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove ${_selected.length} manga from library?',
        ),
        content: const Text(
          'The manga rows stay in the database (read history kept) but '
          'disappear from the Library tab.',
        ),
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
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final ids = _selected.toList(growable: false);
    for (final id in ids) {
      await mangaRepo.setFavorite(id, false);
      // Clear category memberships so re-adding starts clean.
      await categoryRepo.setCategoriesForManga(id, const <int>{});
    }
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(
      SnackBar(content: Text('${ids.length} removed from library')),
    );
  }

  Future<void> _selectionMoveToCategory() async {
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final allCats = await categoryRepo.getAll();
    final userCats = allCats
        .where((c) => !c.isSystemCategory)
        .toList(growable: false);
    if (!mounted) return;
    if (userCats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No categories yet. Create one in More -> Categories first.',
          ),
        ),
      );
      return;
    }
    final selectedIds = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BulkCategorySheet(categories: userCats),
    );
    if (selectedIds == null) return;
    final ids = _selected.toList(growable: false);
    for (final mangaId in ids) {
      await categoryRepo.setCategoriesForManga(mangaId, selectedIds);
    }
    if (!mounted) return;
    _clearSelection();
  }

  /// Foreground library update. Independent of the workmanager schedule.
  Future<void> _refreshLibrary() async {
    if (_updating) return;
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updater = ref.read(libraryUpdaterProvider);
      final result = await updater.updateAll();
      if (!mounted) return;
      final msg = result.newChapters == 0
          ? 'No new chapters found.'
          : '${result.newChapters} new chapter'
              '${result.newChapters == 1 ? '' : 's'} added.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryRepo = ref.watch(libraryRepositoryProvider);
    final categoryRepo = ref.watch(categoryRepositoryProvider);
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final sortPref = ref.watch(librarySortProvider);

    return Scaffold(
      appBar: _selecting ? _buildSelectionAppBar() : AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search library',
                  border: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.titleLarge,
              )
            : const Text('Library'),
        actions: [
          IconButton(
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh library',
            onPressed: _updating ? null : _refreshLibrary,
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _filters.isActive
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter',
            onPressed: () async {
              final next = await showModalBottomSheet<LibraryFilters>(
                context: context,
                showDragHandle: true,
                builder: (_) => _LibraryFilterSheet(current: _filters),
              );
              if (next != null) setState(() => _filters = next);
            },
          ),
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_searching) {
                  _searching = false;
                  _searchController.clear();
                  _query = '';
                } else {
                  _searching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => const _LibrarySortSheet(),
              );
            },
          ),
          PopupMenuButton<LibraryDisplayMode>(
            icon: const Icon(Icons.view_module),
            initialValue: displayMode,
            onSelected: (mode) => ref
                .read(libraryDisplayModeProvider.notifier)
                .setMode(mode),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: LibraryDisplayMode.comfortableGrid,
                child: Text('Comfortable grid'),
              ),
              PopupMenuItem(
                value: LibraryDisplayMode.compactGrid,
                child: Text('Compact grid'),
              ),
              PopupMenuItem(
                value: LibraryDisplayMode.coverOnlyGrid,
                child: Text('Cover only'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<LibraryItem>>(
        stream: libraryRepo.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const _EmptyLibrary();
          }
          return StreamBuilder<List<Category>>(
            stream: categoryRepo.watchAll(),
            builder: (context, catSnap) {
              final categories = catSnap.data ?? const <Category>[];
              return _LibraryBody(
                items: items,
                categories: categories,
                query: _query,
                sort: sortPref,
                filters: _filters,
                displayMode: displayMode,
                selectedCategoryId: _selectedCategoryId,
                onCategoryChanged: (id) =>
                    setState(() => _selectedCategoryId = id),
                onRefresh: _refreshLibrary,
                selected: _selected,
                selecting: _selecting,
                onToggleSelected: _toggleSelected,
              );
            },
          );
        },
      ),
    );
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.items,
    required this.categories,
    required this.query,
    required this.sort,
    required this.filters,
    required this.displayMode,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.onRefresh,
    required this.selected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final List<LibraryItem> items;
  final List<Category> categories;
  final String query;
  final LibrarySortPref sort;
  final LibraryFilters filters;
  final LibraryDisplayMode displayMode;
  final int selectedCategoryId;
  final ValueChanged<int> onCategoryChanged;
  final Future<void> Function() onRefresh;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  @override
  Widget build(BuildContext context) {
    // Determine which categories actually contain at least one item; we
    // only show tabs when there's something to switch between.
    final usedIds = <int>{};
    for (final item in items) {
      usedIds.addAll(item.categoryIds);
    }
    // Filter the user-defined categories down to those with items. The
    // system "uncategorized" (id=0) is included implicitly if any item is
    // there.
    final visibleCategories = [
      for (final c in categories)
        if (usedIds.contains(c.id)) c,
    ]..sort((a, b) => a.order.compareTo(b.order));
    final hasUncategorized = usedIds.contains(Category.uncategorizedId);
    final tabIds = <int>[
      if (hasUncategorized) Category.uncategorizedId,
      ...visibleCategories.map((c) => c.id),
    ];
    // If there's only one effective bucket, hide the tabs entirely.
    final showTabs = tabIds.length > 1;

    // Pick the active id. Default to the first available tab if the
    // currently-selected one disappeared.
    final activeId = showTabs && !tabIds.contains(selectedCategoryId)
        ? tabIds.first
        : selectedCategoryId;

    final filteredByCategory = showTabs
        ? items.where((it) => it.inCategory(activeId)).toList(growable: false)
        : items;

    final qLower = query.toLowerCase();
    final filteredByQuery = qLower.isEmpty
        ? filteredByCategory
        : filteredByCategory
            .where((it) => it.manga.title.toLowerCase().contains(qLower))
            .toList(growable: false);

    final filtered = filters.isActive
        ? filteredByQuery
            .where(filters.matches)
            .toList(growable: false)
        : filteredByQuery;

    final sorted = [...filtered]..sort(_compare(sort));

    return Column(
      children: [
        if (showTabs)
          _CategoryTabs(
            tabIds: tabIds,
            categories: visibleCategories,
            activeId: activeId,
            countFor: (id) =>
                items.where((it) => it.inCategory(id)).length,
            onTabSelected: onCategoryChanged,
          ),
        Expanded(
          child: sorted.isEmpty
              ? _EmptyMatches(query: query)
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: _LibraryGrid(
                    items: sorted,
                    displayMode: displayMode,
                    selected: selected,
                    selecting: selecting,
                    onToggleSelected: onToggleSelected,
                  ),
                ),
        ),
      ],
    );
  }

  int Function(LibraryItem, LibraryItem) _compare(LibrarySortPref sort) {
    int asc(LibraryItem a, LibraryItem b) {
      switch (sort.axis) {
        case LibrarySortAxis.title:
          return a.manga.title
              .toLowerCase()
              .compareTo(b.manga.title.toLowerCase());
        case LibrarySortAxis.lastRead:
          return a.lastRead.compareTo(b.lastRead);
        case LibrarySortAxis.lastUpdate:
          return a.manga.lastUpdate.compareTo(b.manga.lastUpdate);
        case LibrarySortAxis.unread:
          return a.unreadCount.compareTo(b.unreadCount);
        case LibrarySortAxis.totalChapters:
          return a.totalCount.compareTo(b.totalCount);
        case LibrarySortAxis.latestChapter:
          return a.latestUpload.compareTo(b.latestUpload);
        case LibrarySortAxis.chapterFetchDate:
          return a.chapterFetchedAt.compareTo(b.chapterFetchedAt);
        case LibrarySortAxis.dateAdded:
          return a.manga.dateAdded.compareTo(b.manga.dateAdded);
      }
    }
    return sort.direction == LibrarySortDirection.ascending
        ? asc
        : (a, b) => asc(b, a);
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.tabIds,
    required this.categories,
    required this.activeId,
    required this.countFor,
    required this.onTabSelected,
  });

  final List<int> tabIds;
  final List<Category> categories;
  final int activeId;
  final int Function(int categoryId) countFor;
  final ValueChanged<int> onTabSelected;

  String _labelFor(int id) {
    if (id == Category.uncategorizedId) return 'Default';
    return categories.firstWhere((c) => c.id == id).name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: tabIds.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final id = tabIds[i];
            final selected = id == activeId;
            final count = countFor(id);
            return Center(
              child: ChoiceChip(
                selected: selected,
                label: Text('${_labelFor(id)} ($count)'),
                onSelected: (_) => onTabSelected(id),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.items,
    required this.displayMode,
    required this.selected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final List<LibraryItem> items;
  final LibraryDisplayMode displayMode;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  @override
  Widget build(BuildContext context) {
    // Cover-only fits more per row because there's no title row eating
    // space below the cover.
    final maxExtent = displayMode == LibraryDisplayMode.coverOnlyGrid
        ? 120.0
        : 140.0;
    final aspectRatio =
        displayMode == LibraryDisplayMode.comfortableGrid ? 0.58 : 0.66;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _MangaCard(
        item: items[i],
        displayMode: displayMode,
        isSelected: selected.contains(items[i].manga.id),
        selecting: selecting,
        onToggleSelected: onToggleSelected,
      ),
    );
  }
}

class _MangaCard extends ConsumerWidget {
  const _MangaCard({
    required this.item,
    required this.displayMode,
    required this.isSelected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final LibraryItem item;
  final LibraryDisplayMode displayMode;
  final bool isSelected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(mangaId: item.manga.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manga = item.manga;
    final showCoverOverlayTitle =
        displayMode == LibraryDisplayMode.compactGrid;
    final showTitleBelow =
        displayMode == LibraryDisplayMode.comfortableGrid;
    final downloadRepo = ref.watch(downloadRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: scheme.primary, width: 3)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          if (selecting) {
            onToggleSelected(manga.id);
          } else {
            _open(context);
          }
        },
        onLongPress: () => onToggleSelected(manga.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(manga: manga),
                  // Top-start badge: unread count.
                  if (item.unreadCount > 0)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: _UnreadBadge(count: item.unreadCount),
                    ),
                  // Top-end badge: count of fully-downloaded chapters.
                  // Counted via filesystem probe; the future is
                  // re-issued whenever the card rebuilds (so adding a
                  // download then navigating away & back picks it up).
                  Positioned(
                    top: 4,
                    right: 4,
                    child: FutureBuilder<int>(
                      future: downloadRepo.countDownloadedForManga(
                        manga.source,
                        manga.id,
                      ),
                      builder: (context, snap) {
                        final n = snap.data ?? 0;
                        if (n <= 0) return const SizedBox.shrink();
                        return _DownloadedBadge(count: n);
                      },
                    ),
                  ),
                  if (showCoverOverlayTitle)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _CoverTitleOverlay(title: manga.title),
                    ),
                  // Selection scrim + check icon. Drawn on top of every
                  // other overlay so the selection state is obvious.
                  if (isSelected)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.primary.withValues(alpha: 0.35),
                        child: Center(
                          child: Icon(
                            Icons.check_circle,
                            size: 36,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showTitleBelow)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  manga.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Top-end badge showing the number of fully-downloaded chapters. Used
/// alongside the unread badge so the cover can advertise both states
/// without competing for the same corner. Mihon's badge palette: green
/// tertiary for downloaded, primary for unread.
class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _CoverTitleOverlay extends StatelessWidget {
  const _CoverTitleOverlay({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xCC000000)],
        ),
      ),
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w500,
          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
    );
  }
}

/// Bottom sheet for the bulk "Move to category" action. Returns the set
/// of category ids the user picked (empty Set means "no categories" —
/// the manga ends up in Uncategorized). Cancel returns null so the
/// caller leaves memberships untouched.
class _BulkCategorySheet extends StatefulWidget {
  const _BulkCategorySheet({required this.categories});

  final List<Category> categories;

  @override
  State<_BulkCategorySheet> createState() => _BulkCategorySheetState();
}

class _BulkCategorySheetState extends State<_BulkCategorySheet> {
  final Set<int> _picked = <int>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Move to category',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.categories.map((c) {
                  final checked = _picked.contains(c.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _picked.add(c.id);
                        } else {
                          _picked.remove(c.id);
                        }
                      });
                    },
                    title: Text(c.name),
                  );
                }).toList(growable: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_picked),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book, size: 48),
      );
    }
    return SourceImage(
      url: url,
      fit: BoxFit.cover,
      placeholder: (_) => Container(color: placeholderColor),
      errorWidget: (_, _) => Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, size: 36),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_bookmark_outlined, size: 64),
          const SizedBox(height: 12),
          Text(
            'Your library is empty.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Use the Browse tab to add manga to your library.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          query.isEmpty
              ? 'Nothing in this category yet.'
              : 'No matches for "$query".',
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load library: $error',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Tri-state filter sheet for the library grid. Each row cycles
/// disabled → include → exclude → disabled on tap. A 'Reset' action
/// clears everything; 'Apply' pops the sheet with the new state.
class _LibraryFilterSheet extends StatefulWidget {
  const _LibraryFilterSheet({required this.current});

  final LibraryFilters current;

  @override
  State<_LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<_LibraryFilterSheet> {
  late LibraryFilters _draft = widget.current;

  TriState _cycle(TriState v) {
    switch (v) {
      case TriState.disabled:
        return TriState.enabledIs;
      case TriState.enabledIs:
        return TriState.enabledNot;
      case TriState.enabledNot:
        return TriState.disabled;
    }
  }

  IconData _icon(TriState v) {
    switch (v) {
      case TriState.disabled:
        return Icons.check_box_outline_blank;
      case TriState.enabledIs:
        return Icons.check_box;
      case TriState.enabledNot:
        return Icons.indeterminate_check_box;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Filters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _draft.isActive
                        ? () => setState(() => _draft = const LibraryFilters())
                        : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            _FilterRow(
              label: 'Unread',
              icon: _icon(_draft.unread),
              onTap: () => setState(
                () => _draft = _draft.copyWith(unread: _cycle(_draft.unread)),
              ),
            ),
            _FilterRow(
              label: 'Started',
              icon: _icon(_draft.started),
              onTap: () => setState(
                () => _draft =
                    _draft.copyWith(started: _cycle(_draft.started)),
              ),
            ),
            _FilterRow(
              label: 'Bookmarked',
              icon: _icon(_draft.bookmarked),
              onTap: () => setState(
                () => _draft = _draft.copyWith(
                  bookmarked: _cycle(_draft.bookmarked),
                ),
              ),
            ),
            _FilterRow(
              label: 'Completed',
              icon: _icon(_draft.completed),
              onTap: () => setState(
                () => _draft = _draft.copyWith(
                  completed: _cycle(_draft.completed),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}

/// Mihon-style sort sheet: lists every sort axis with an asc/desc arrow
/// on the currently-active axis. Tapping the active row flips direction;
/// tapping a different row switches axes (preserving direction). Writes
/// back through the `librarySortProvider` so the choice persists.
class _LibrarySortSheet extends ConsumerWidget {
  const _LibrarySortSheet();

  static const _entries = <(LibrarySortAxis, String)>[
    (LibrarySortAxis.title, 'Alphabetical'),
    (LibrarySortAxis.lastRead, 'Last read'),
    (LibrarySortAxis.lastUpdate, 'Last update'),
    (LibrarySortAxis.unread, 'Unread count'),
    (LibrarySortAxis.totalChapters, 'Total chapters'),
    (LibrarySortAxis.latestChapter, 'Latest chapter'),
    (LibrarySortAxis.chapterFetchDate, 'Chapter fetch date'),
    (LibrarySortAxis.dateAdded, 'Date added'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(librarySortProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Sort by',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final entry in _entries)
              ListTile(
                leading: Icon(
                  entry.$1 == current.axis
                      ? (current.direction == LibrarySortDirection.ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                      : null,
                  color: entry.$1 == current.axis
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(
                  entry.$2,
                  style: entry.$1 == current.axis
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                onTap: () {
                  ref.read(librarySortProvider.notifier).setAxis(entry.$1);
                },
              ),
          ],
        ),
      ),
    );
  }
}
