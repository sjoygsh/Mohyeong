import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_updater.dart';
import '../../domain/category/model/category.dart';
import '../../domain/library/model/library_item.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

enum LibrarySort { titleAsc, dateAddedDesc, lastUpdateDesc, unreadDesc }

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
  LibrarySort _sort = LibrarySort.titleAsc;
  bool _searching = false;
  bool _updating = false;
  int _selectedCategoryId = Category.uncategorizedId;
  late final TextEditingController _searchController =
      TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    return Scaffold(
      appBar: AppBar(
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
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: LibrarySort.titleAsc,
                child: Text('Title (A–Z)'),
              ),
              PopupMenuItem(
                value: LibrarySort.dateAddedDesc,
                child: Text('Recently added'),
              ),
              PopupMenuItem(
                value: LibrarySort.lastUpdateDesc,
                child: Text('Last update'),
              ),
              PopupMenuItem(
                value: LibrarySort.unreadDesc,
                child: Text('Most unread'),
              ),
            ],
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
                sort: _sort,
                displayMode: displayMode,
                selectedCategoryId: _selectedCategoryId,
                onCategoryChanged: (id) =>
                    setState(() => _selectedCategoryId = id),
                onRefresh: _refreshLibrary,
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
    required this.displayMode,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.onRefresh,
  });

  final List<LibraryItem> items;
  final List<Category> categories;
  final String query;
  final LibrarySort sort;
  final LibraryDisplayMode displayMode;
  final int selectedCategoryId;
  final ValueChanged<int> onCategoryChanged;
  final Future<void> Function() onRefresh;

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
    final filtered = qLower.isEmpty
        ? filteredByCategory
        : filteredByCategory
            .where((it) => it.manga.title.toLowerCase().contains(qLower))
            .toList(growable: false);

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
                  ),
                ),
        ),
      ],
    );
  }

  int Function(LibraryItem, LibraryItem) _compare(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.titleAsc:
        return (a, b) => a.manga.title
            .toLowerCase()
            .compareTo(b.manga.title.toLowerCase());
      case LibrarySort.dateAddedDesc:
        return (a, b) => b.manga.dateAdded.compareTo(a.manga.dateAdded);
      case LibrarySort.lastUpdateDesc:
        return (a, b) => b.manga.lastUpdate.compareTo(a.manga.lastUpdate);
      case LibrarySort.unreadDesc:
        return (a, b) => b.unreadCount.compareTo(a.unreadCount);
    }
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
  });

  final List<LibraryItem> items;
  final LibraryDisplayMode displayMode;

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
      ),
    );
  }
}

class _MangaCard extends StatelessWidget {
  const _MangaCard({
    required this.item,
    required this.displayMode,
  });

  final LibraryItem item;
  final LibraryDisplayMode displayMode;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(mangaId: item.manga.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manga = item.manga;
    final showCoverOverlayTitle =
        displayMode == LibraryDisplayMode.compactGrid;
    final showTitleBelow =
        displayMode == LibraryDisplayMode.comfortableGrid;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
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
                  if (showCoverOverlayTitle)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _CoverTitleOverlay(title: manga.title),
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
