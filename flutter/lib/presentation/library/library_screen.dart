import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/cover/cover_cache.dart';
import '../../data/download/download_repository.dart';
import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_updater.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/notification/notification_service.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/local_source.dart';
import '../../data/track/track_repository.dart';
import '../../domain/category/model/category.dart';
import '../../domain/library/model/library_item.dart';
import '../../domain/chapter/service/set_read_status.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../common/source_image.dart';
import '../home/home_screen.dart';
import '../manga/manga_details_screen.dart';
import '../reader/reader_screen.dart';

/// Tri-state filters for the library grid. Each axis can be off (show
/// everything), include-only (show rows where the predicate matches),
/// or exclude (show rows where it doesn't). Mirrors Mihon's library
/// filter sheet. The Downloaded axis needs an async-resolved set of
/// `(sourceId, mangaId)` keys (filesystem walk) — when active, the
/// body wraps the pipeline in a FutureBuilder and passes the set in.
class LibraryFilters {
  const LibraryFilters({
    this.unread = TriState.disabled,
    this.started = TriState.disabled,
    this.bookmarked = TriState.disabled,
    this.completed = TriState.disabled,
    this.downloaded = TriState.disabled,
    this.tracked = TriState.disabled,
  });

  final TriState unread;
  final TriState started;
  final TriState bookmarked;
  final TriState completed;
  final TriState downloaded;
  final TriState tracked;

  bool get isActive =>
      unread != TriState.disabled ||
      started != TriState.disabled ||
      bookmarked != TriState.disabled ||
      completed != TriState.disabled ||
      downloaded != TriState.disabled ||
      tracked != TriState.disabled;

  /// Mihon stores publication status as ints; `2` is "Completed".
  static const int _statusCompleted = 2;

  /// [downloadedKeys] is the set of `DownloadRepository.encodeMangaKey`
  /// results for every manga that has at least one fully-downloaded
  /// chapter. [trackedMangaIds] is the set of mangaIds that have at
  /// least one tracker row. Pass null when the corresponding axis is
  /// disabled; the predicate short-circuits in that case.
  bool matches(
    LibraryItem item, {
    Set<int>? downloadedKeys,
    Set<int>? trackedMangaIds,
  }) {
    if (!applyTriState(unread, () => item.unreadCount > 0)) return false;
    if (!applyTriState(started, () => item.readCount > 0)) return false;
    if (!applyTriState(bookmarked, () => item.bookmarkCount > 0)) return false;
    if (!applyTriState(
        completed, () => item.manga.status == _statusCompleted)) {
      return false;
    }
    if (downloaded != TriState.disabled) {
      final keys = downloadedKeys ?? const <int>{};
      final key = DownloadRepository.encodeMangaKey(
        item.manga.source,
        item.manga.id,
      );
      if (!applyTriState(downloaded, () => keys.contains(key))) return false;
    }
    if (tracked != TriState.disabled) {
      final ids = trackedMangaIds ?? const <int>{};
      if (!applyTriState(tracked, () => ids.contains(item.manga.id))) {
        return false;
      }
    }
    return true;
  }

  LibraryFilters copyWith({
    TriState? unread,
    TriState? started,
    TriState? bookmarked,
    TriState? completed,
    TriState? downloaded,
    TriState? tracked,
  }) {
    return LibraryFilters(
      unread: unread ?? this.unread,
      started: started ?? this.started,
      bookmarked: bookmarked ?? this.bookmarked,
      completed: completed ?? this.completed,
      downloaded: downloaded ?? this.downloaded,
      tracked: tracked ?? this.tracked,
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

  // Ids of the entries currently visible in the grid (after category tab,
  // search and filter narrowing). Updated by [_LibraryBody] during its build
  // so "Select all" / "Invert selection" operate on the displayed set —
  // mirrors Mihon, where those act on the active category's items.
  List<int> _visibleIds = const <int>[];

  bool get _selecting => _selected.isNotEmpty;

  void _selectAllVisible() {
    setState(() => _selected.addAll(_visibleIds));
  }

  void _invertVisibleSelection() {
    setState(() {
      for (final id in _visibleIds) {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      }
    });
  }

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

  /// Contextual app bar shown while at least one card is selected. Mirrors
  /// Mihon's `LibrarySelectionToolbar`: a cancel (X) action-mode bar with the
  /// selected count and just two actions — Select all and Invert selection.
  /// The bulk operations live in the bottom action bar
  /// ([_buildSelectionBottomBar]), matching Mihon's `LibraryBottomActionMenu`.
  AppBar _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length}'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Select all',
          onPressed: _selectAllVisible,
        ),
        IconButton(
          icon: const Icon(Icons.flip_to_back),
          tooltip: 'Invert selection',
          onPressed: _invertVisibleSelection,
        ),
      ],
    );
  }

  /// Bottom action bar for library selection mode. Mirrors Mihon's
  /// `LibraryBottomActionMenu`: Move to category, Mark read, Mark unread,
  /// Download, Delete. (Bulk Migrate is not yet wired — single-entry
  /// migration only.)
  Widget _buildSelectionBottomBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Move to category',
            onPressed: _selectionMoveToCategory,
          ),
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
          PopupMenuButton<int?>(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download chapters',
            onSelected: _selectionDownloadNext,
            itemBuilder: (_) => const [
              PopupMenuItem<int?>(value: 1, child: Text('Next 1 chapter')),
              PopupMenuItem<int?>(value: 5, child: Text('Next 5 chapters')),
              PopupMenuItem<int?>(value: 10, child: Text('Next 10 chapters')),
              PopupMenuItem<int?>(value: 25, child: Text('Next 25 chapters')),
              PopupMenuItem<int?>(
                value: null,
                child: Text('All unread chapters'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove from library',
            onPressed: _selectionRemoveFromLibrary,
          ),
        ],
      ),
    );
  }

  /// Bulk download for selected manga: for each, fetch its chapters, sort
  /// by `sourceOrder` ascending (matches `_pickNextUnread`), take the
  /// first [count] unread (null = all) and enqueue each. Relies on
  /// `DownloadRepository.enqueue` being idempotent for already-queued or
  /// already-downloaded chapters.
  Future<void> _selectionDownloadNext(int? count) async {
    final messenger = ScaffoldMessenger.of(context);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final downloadRepo = ref.read(downloadRepositoryProvider);
    final ids = _selected.toList(growable: false);
    var enqueued = 0;
    for (final id in ids) {
      final manga = await mangaRepo.getById(id);
      if (manga == null) continue;
      final chapters = await chapterRepo.getByMangaId(id);
      final unread = chapters.where((c) => !c.read).toList()
        ..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
      final take = count == null ? unread : unread.take(count).toList();
      for (final c in take) {
        await downloadRepo.enqueue(manga, c);
        enqueued++;
      }
    }
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(SnackBar(
      content: Text(enqueued == 0
          ? 'No unread chapters to download.'
          : 'Enqueued $enqueued chapter${enqueued == 1 ? '' : 's'}.'),
    ));
  }

  Future<void> _selectionMarkRead(bool read) async {
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final setReadStatus = ref.read(setReadStatusProvider);
    final ids = _selected.toList(growable: false);
    for (final id in ids) {
      final chapters = await chapterRepo.getByMangaId(id);
      await setReadStatus.setRead(read: read, chapters: chapters);
    }
    if (!mounted) return;
    _clearSelection();
  }

  Future<void> _selectionRemoveFromLibrary() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_RemoveResult>(
      context: context,
      builder: (ctx) =>
          _RemoveLibraryDialog(count: _selected.length),
    );
    if (result == null) return;
    if (!result.remove && !result.deleteDownloads) return;
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final downloadRepo =
        result.deleteDownloads ? ref.read(downloadRepositoryProvider) : null;
    final ids = _selected.toList(growable: false);
    for (final id in ids) {
      final manga = await mangaRepo.getById(id);
      if (result.remove) {
        await mangaRepo.setFavorite(id, false);
        // Clear category memberships so re-adding starts clean.
        await categoryRepo.setCategoriesForManga(id, const <int>{});
      }
      if (downloadRepo != null && manga != null) {
        await downloadRepo.deleteAllForManga(manga.source, manga.id);
      }
    }
    if (!mounted) return;
    _clearSelection();
    final msg = result.remove && result.deleteDownloads
        ? '${ids.length} removed (downloads deleted)'
        : result.remove
            ? '${ids.length} removed from library'
            : 'Downloads deleted for ${ids.length} manga';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
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

  /// Opens the tabbed Filter / Sort / Display settings sheet. Mirrors
  /// Mihon's LibrarySettingsDialog (a TabbedDialog). Filter changes apply
  /// live through [_filters]; sort/display changes write straight to their
  /// providers, so there are no Apply/Cancel buttons.
  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LibrarySettingsSheet(
        current: _filters,
        onFiltersChanged: (next) => setState(() => _filters = next),
      ),
    );
  }

  /// "Open random entry": pick a random favourite from the active category
  /// (respecting the current search query) and open its details. Mirrors
  /// Mihon's `getRandomLibraryItemForCurrentCategory`.
  Future<void> _openRandomEntry() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final items = await ref.read(libraryRepositoryProvider).watchAll().first;
    final inCategory = items
        .where((it) => it.inCategory(_selectedCategoryId))
        .toList(growable: false);
    final pool = inCategory.isEmpty ? items : inCategory;
    if (pool.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No entries found.')),
      );
      return;
    }
    final pick = (pool.toList()..shuffle()).first;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(mangaId: pick.manga.id),
      ),
    );
  }

  /// Foreground library update. Independent of the workmanager schedule.
  /// When [categoryId] is non-null only manga belonging to that category
  /// are refreshed — used by the "Update this category" affordance.
  Future<void> _refreshLibrary({int? categoryId}) async {
    if (_updating) return;
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    final notifications = NotificationService.instance;
    try {
      final updater = ref.read(libraryUpdaterProvider);
      // Mirror Mihon's foreground-update progress notification.
      void onProgress(LibraryUpdateProgress p) {
        if (p.currentTitle == null) {
          notifications.cancelLibraryProgress();
        } else {
          notifications.showLibraryProgress(
            current: p.completed,
            total: p.total,
            title: p.currentTitle!,
          );
        }
      }

      final result = categoryId == null
          ? await updater.updateAll(onProgress: onProgress)
          : await updater.updateCategory(categoryId, onProgress: onProgress);
      await notifications.cancelLibraryProgress();
      await notifications.showNewChapters(
        mangaCount: result.mangaWithNewChapters,
        chapterCount: result.newChapters,
      );
      await notifications.showLibraryErrors(result.failures.length);
      if (!mounted) return;
      final msg = result.newChapters == 0
          ? 'No new chapters found.'
          : '${result.newChapters} new chapter'
              '${result.newChapters == 1 ? '' : 's'} added.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      await notifications.cancelLibraryProgress();
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

    // Library is tab 0. Mirrors Kotlin `LibraryTab.onReselect`: tapping the
    // already-active Library destination opens the settings sheet.
    ref.listen<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab == 0 && next.tick != (prev?.tick ?? 0)) {
        _showSettingsSheet();
      }
    });

    return Scaffold(
      bottomNavigationBar:
          _selecting ? _buildSelectionBottomBar() : null,
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
            : _LibraryTitle(selectedCategoryId: _selectedCategoryId),
        actions: [
          // Mirrors Mihon's LibraryToolbar: a single Filter icon (active-
          // tinted when any filter is set) opens the tabbed Filter/Sort/
          // Display sheet; the search icon toggles the in-place search field;
          // the overflow folds the library-update + random-entry actions.
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: 'Search',
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
            icon: Icon(
              Icons.filter_list,
              color: _filters.isActive
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter',
            onPressed: _showSettingsSheet,
          ),
          PopupMenuButton<_LibraryMenuAction>(
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            onSelected: (action) {
              switch (action) {
                case _LibraryMenuAction.updateLibrary:
                  _refreshLibrary();
                case _LibraryMenuAction.updateCategory:
                  _refreshLibrary(categoryId: _selectedCategoryId);
                case _LibraryMenuAction.openRandom:
                  _openRandomEntry();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _LibraryMenuAction.updateLibrary,
                enabled: !_updating,
                child: const Text('Update library'),
              ),
              PopupMenuItem(
                value: _LibraryMenuAction.updateCategory,
                enabled: !_updating,
                child: const Text('Update category'),
              ),
              const PopupMenuItem(
                value: _LibraryMenuAction.openRandom,
                child: Text('Open random entry'),
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
              // Both the Downloaded and Tracked axes need async-resolved
              // sets. Resolve them in parallel only when at least one is
              // enabled — most users never enable either.
              final needsDownloaded =
                  _filters.downloaded != TriState.disabled;
              final needsTracked = _filters.tracked != TriState.disabled;
              if (needsDownloaded || needsTracked) {
                final downloadRepo = ref.watch(downloadRepositoryProvider);
                final trackRepo = ref.watch(trackRepositoryProvider);
                return FutureBuilder<_AsyncFilterSets>(
                  future: _resolveAsyncFilterSets(
                    downloadRepo: needsDownloaded ? downloadRepo : null,
                    trackRepo: needsTracked ? trackRepo : null,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final sets = snap.data!;
                    return _LibraryBody(
                      items: items,
                      categories: categories,
                      query: _query,
                      sort: sortPref,
                      filters: _filters,
                      downloadedKeys: sets.downloadedKeys,
                      trackedMangaIds: sets.trackedMangaIds,
                      displayMode: displayMode,
                      selectedCategoryId: _selectedCategoryId,
                      onCategoryChanged: (id) =>
                          setState(() => _selectedCategoryId = id),
                      onRefresh: _refreshLibrary,
                      selected: _selected,
                      selecting: _selecting,
                      onToggleSelected: _toggleSelected,
                      onVisibleIdsResolved: (ids) => _visibleIds = ids,
                    );
                  },
                );
              }
              return _LibraryBody(
                items: items,
                categories: categories,
                query: _query,
                sort: sortPref,
                filters: _filters,
                downloadedKeys: null,
                trackedMangaIds: null,
                displayMode: displayMode,
                selectedCategoryId: _selectedCategoryId,
                onCategoryChanged: (id) =>
                    setState(() => _selectedCategoryId = id),
                onRefresh: _refreshLibrary,
                selected: _selected,
                selecting: _selecting,
                onToggleSelected: _toggleSelected,
                onVisibleIdsResolved: (ids) => _visibleIds = ids,
              );
            },
          );
        },
      ),
    );
  }
}

/// Overflow-menu actions on the library toolbar. Mirrors Mihon's
/// LibraryToolbar overflow: "Update library" (sweep every favourite),
/// "Update category" (only the active category tab), and "Open random
/// entry" (jump to a random manga in the current category).
enum _LibraryMenuAction { updateLibrary, updateCategory, openRandom }

/// Holds the async-resolved sets that the filter predicate needs when
/// either the Downloaded or Tracked axis is active. Either field may be
/// null if its corresponding axis was disabled at resolve time.
class _AsyncFilterSets {
  const _AsyncFilterSets({this.downloadedKeys, this.trackedMangaIds});
  final Set<int>? downloadedKeys;
  final Set<int>? trackedMangaIds;
}

/// Resolves the two async sets in parallel. Skipped sides are returned
/// as null rather than empty so the predicate can short-circuit.
Future<_AsyncFilterSets> _resolveAsyncFilterSets({
  DownloadRepository? downloadRepo,
  TrackRepository? trackRepo,
}) async {
  final dlFut = downloadRepo?.listMangaWithAnyDownload();
  final trFut = trackRepo?.getAll();
  final dl = dlFut == null ? null : await dlFut;
  final tracks = trFut == null ? null : await trFut;
  return _AsyncFilterSets(
    downloadedKeys: dl,
    trackedMangaIds:
        tracks == null ? null : {for (final t in tracks) t.mangaId},
  );
}

/// Resolves the next unread chapter for [mangaId] and opens the reader on
/// it, mirroring Mihon's library continue-reading button. "Next unread" is
/// the first chapter (by `sourceOrder` ascending) whose `read` flag is
/// false — the same ordering the bulk-download path uses. No-op with a
/// snackbar when everything is read. [ref] must outlive the await (read,
/// not watch).
Future<void> _resumeNextUnread(
  BuildContext context,
  WidgetRef ref,
  int mangaId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final chapters = await ref.read(chapterRepositoryProvider).getByMangaId(
        mangaId,
      );
  final unread = chapters.where((c) => !c.read).toList()
    ..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
  if (unread.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No unread chapters left.')),
    );
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        mangaId: mangaId,
        chapterId: unread.first.id,
      ),
    ),
  );
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({
    required this.items,
    required this.categories,
    required this.query,
    required this.sort,
    required this.filters,
    required this.downloadedKeys,
    required this.trackedMangaIds,
    required this.displayMode,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.onRefresh,
    required this.selected,
    required this.selecting,
    required this.onToggleSelected,
    required this.onVisibleIdsResolved,
  });

  final List<LibraryItem> items;
  final List<Category> categories;
  final String query;
  final LibrarySortPref sort;
  final LibraryFilters filters;
  final Set<int>? downloadedKeys;
  final Set<int>? trackedMangaIds;
  final LibraryDisplayMode displayMode;
  final int selectedCategoryId;
  final ValueChanged<int> onCategoryChanged;
  final Future<void> Function() onRefresh;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  /// Reports the ids currently shown in the grid (post category/search/filter
  /// narrowing) so the parent's Select-all / Invert actions act on them.
  final ValueChanged<List<int>> onVisibleIdsResolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // Tabs follow Mihon's `showPageTabs`: shown when the "Show category tabs"
    // pref is on OR a search is active — but still hidden when there's only
    // one effective bucket to switch between. The per-tab count follows the
    // "Show number of items" pref (or an active search), per Mihon's
    // `getItemCountForCategory`.
    final searching = query.isNotEmpty;
    final showCategoryTabsPref = ref.watch(categoryTabsProvider);
    final showCount = ref.watch(categoryNumberOfItemsProvider) || searching;
    final showTabs =
        (showCategoryTabsPref || searching) && tabIds.length > 1;

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
            .where((it) => filters.matches(
                  it,
                  downloadedKeys: downloadedKeys,
                  trackedMangaIds: trackedMangaIds,
                ))
            .toList(growable: false)
        : filteredByQuery;

    // Random sort shuffles deterministically against the persisted seed
    // (regenerated whenever the user re-picks Random); every other axis uses
    // the comparator.
    final sorted = sort.axis == LibrarySortAxis.random
        ? ([...filtered]..shuffle(math.Random(ref.watch(randomSortSeedProvider))))
        : ([...filtered]..sort(_compare(sort)));

    // Surface the visible ids so the toolbar's Select-all / Invert act on the
    // displayed set. Pure assignment in the parent (no setState), so it's safe
    // to call during build.
    onVisibleIdsResolved(
      sorted.map((it) => it.manga.id).toList(growable: false),
    );

    // "Most read" carousel — top 5 favourites by completion ratio
    // (`readCount / totalCount`), only entries the user has actually
    // started. Hidden while searching and when the pref is off. Sourced
    // from the unfiltered favourites list, not the category-restricted
    // one, since the carousel is a global "what are you working
    // through" affordance.
    final showCarousel = ref.watch(showMostReadCarouselProvider);
    final showCarouselNow = showCarousel && query.isEmpty;
    final topRead = showCarouselNow
        ? (items
                .where((it) => it.totalCount > 0 && it.readCount > 0)
                .toList(growable: false)
              ..sort((a, b) {
                final aRatio = a.readCount / a.totalCount;
                final bRatio = b.readCount / b.totalCount;
                return bRatio.compareTo(aRatio);
              }))
            .take(5)
            .toList(growable: false)
        : const <LibraryItem>[];

    return Column(
      children: [
        if (showCarouselNow && topRead.isNotEmpty)
          _MostReadCarousel(items: topRead),
        if (showTabs)
          _CategoryTabs(
            tabIds: tabIds,
            categories: visibleCategories,
            activeId: activeId,
            showCount: showCount,
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
                    columns: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? ref.watch(landscapeColumnsProvider)
                        : ref.watch(portraitColumnsProvider),
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
        case LibrarySortAxis.random:
          // Handled by the seeded shuffle in build(); never reached here.
          return 0;
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
    required this.showCount,
    required this.countFor,
    required this.onTabSelected,
  });

  final List<int> tabIds;
  final List<Category> categories;
  final int activeId;
  final bool showCount;
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
            final label = showCount
                ? '${_labelFor(id)} (${countFor(id)})'
                : _labelFor(id);
            return Center(
              child: ChoiceChip(
                selected: selected,
                label: Text(label),
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
    required this.columns,
    required this.selected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final List<LibraryItem> items;
  final LibraryDisplayMode displayMode;

  /// Fixed columns per row; 0 = Auto (derive from cover width).
  final int columns;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  @override
  Widget build(BuildContext context) {
    if (displayMode == LibraryDisplayMode.list) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _MangaListTile(
          item: items[i],
          isSelected: selected.contains(items[i].manga.id),
          selecting: selecting,
          onToggleSelected: onToggleSelected,
        ),
      );
    }
    // Cover-only fits more per row because there's no title row eating
    // space below the cover.
    final maxExtent = displayMode == LibraryDisplayMode.coverOnlyGrid
        ? 120.0
        : 140.0;
    final aspectRatio =
        displayMode == LibraryDisplayMode.comfortableGrid ? 0.58 : 0.66;
    // 0 columns = Auto: fall back to a max-extent delegate that picks the
    // column count from the cover width. A fixed count honours the user's
    // "Items per row" slider.
    final gridDelegate = columns > 0
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          )
        : SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          );
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: gridDelegate,
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

/// Single-row tile for `LibraryDisplayMode.list`. Mirrors Mihon's
/// `LibraryList`: 40x56 thumbnail on the left, title (1 line) + author
/// (1 line) in the middle, unread + downloaded badges on the right.
/// Long-press toggles selection (consistent with the grid modes).
class _MangaListTile extends ConsumerWidget {
  const _MangaListTile({
    required this.item,
    required this.isSelected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final LibraryItem item;
  final bool isSelected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manga = item.manga;
    final scheme = Theme.of(context).colorScheme;
    final downloadRepo = ref.watch(downloadRepositoryProvider);
    final showUnreadBadge = ref.watch(displayUnreadBadgeProvider);
    final showDownloadBadge = ref.watch(displayDownloadBadgeProvider);
    final showLocalBadge = ref.watch(displayLocalBadgeProvider);
    final showLanguageBadge = ref.watch(displayLanguageBadgeProvider);
    final showContinueReading = ref.watch(showContinueReadingButtonProvider);
    final isLocal = manga.source.toString() == LocalSource.sourceId;
    final sourceLangs = showLanguageBadge
        ? ref.watch(installedSourceLangsProvider).valueOrNull
        : null;
    final lang =
        (sourceLangs != null && !isLocal) ? sourceLangs[manga.source] : null;
    return InkWell(
      onTap: () {
        if (selecting) {
          onToggleSelected(manga.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MangaDetailsScreen(mangaId: manga.id),
            ),
          );
        }
      },
      onLongPress: () => onToggleSelected(manga.id),
      child: Container(
        color: isSelected ? scheme.primary.withValues(alpha: 0.15) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _Cover(manga: manga),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (manga.author != null && manga.author!.isNotEmpty)
                    Text(
                      manga.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showLocalBadge && isLocal)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: _TextChip(text: 'Local'),
              ),
            if (lang != null && lang.isNotEmpty && lang != 'all')
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _TextChip(text: lang.toUpperCase()),
              ),
            if (showUnreadBadge && item.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _UnreadBadge(count: item.unreadCount),
              ),
            if (showDownloadBadge)
              FutureBuilder<int>(
                future: downloadRepo.countDownloadedForManga(
                  manga.source,
                  manga.id,
                ),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  if (n <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _DownloadedBadge(count: n),
                  );
                },
              ),
            if (showContinueReading && !selecting && item.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _ContinueReadingButton(
                  size: 28,
                  onPressed: () => _resumeNextUnread(context, ref, manga.id),
                ),
              ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: scheme.primary),
              ),
          ],
        ),
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
    final showUnreadBadge = ref.watch(displayUnreadBadgeProvider);
    final showDownloadBadge = ref.watch(displayDownloadBadgeProvider);
    final showLocalBadge = ref.watch(displayLocalBadgeProvider);
    final showLanguageBadge = ref.watch(displayLanguageBadgeProvider);
    final showContinueReading = ref.watch(showContinueReadingButtonProvider);
    final isLocal = manga.source.toString() == LocalSource.sourceId;
    final sourceLangs = showLanguageBadge
        ? ref.watch(installedSourceLangsProvider).valueOrNull
        : null;
    final lang =
        (sourceLangs != null && !isLocal) ? sourceLangs[manga.source] : null;
    // Build the top-left badge column: unread on top, then Local/lang
    // chips below it. Each entry is omitted when its toggle is off so
    // the column collapses cleanly.
    final topLeftChildren = <Widget>[
      if (showUnreadBadge && item.unreadCount > 0)
        _UnreadBadge(count: item.unreadCount),
      if (showLocalBadge && isLocal) const _TextChip(text: 'Local'),
      if (lang != null && lang.isNotEmpty && lang != 'all')
        _TextChip(text: lang.toUpperCase()),
    ];

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
                  // Top-start badge column: unread count, then Local /
                  // language chips stacked beneath.
                  if (topLeftChildren.isNotEmpty)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < topLeftChildren.length; i++) ...[
                            if (i > 0) const SizedBox(height: 2),
                            topLeftChildren[i],
                          ],
                        ],
                      ),
                    ),
                  // Top-end badge: count of fully-downloaded chapters.
                  // Counted via filesystem probe; the future is
                  // re-issued whenever the card rebuilds (so adding a
                  // download then navigating away & back picks it up).
                  if (showDownloadBadge)
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
                  // Bottom-end resume button. Only when the pref is on,
                  // there's something unread, and we're not selecting —
                  // matches Mihon's `onClickContinueReading` placement.
                  if (showContinueReading &&
                      !selecting &&
                      item.unreadCount > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _ContinueReadingButton(
                        onPressed: () =>
                            _resumeNextUnread(context, ref, manga.id),
                      ),
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

/// Compact label chip used for the Local / language-code badges.
/// Visually distinct from the unread/downloaded count badges (uses the
/// theme's `secondary` so the count badges stay the primary signal),
/// but the same rounded-rect padding so they line up in a column.
class _TextChip extends StatelessWidget {
  const _TextChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Filled play button overlaid on a card / list row when the
/// continue-reading pref is on. Mirrors Mihon's `ContinueReadingButton`:
/// a small rounded `FilledIconButton` using the `primaryContainer`
/// colour. [size] differs by host (grid corner vs list trailing).
class _ContinueReadingButton extends StatelessWidget {
  const _ContinueReadingButton({
    required this.onPressed,
    this.size = 32,
  });

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        padding: EdgeInsets.zero,
        iconSize: size * 0.6,
        style: IconButton.styleFrom(
          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.9),
          foregroundColor: scheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        tooltip: 'Resume',
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow),
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

class _Cover extends ConsumerWidget {
  const _Cover({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final url =
        ref.watch(coverCacheProvider).coverUrlFor(manga.id, manga.thumbnailUrl);
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

/// Library toolbar title. Mirrors Mihon's `getToolbarTitle`: shows
/// "Library" while category tabs are on, or the active category's name when
/// they're off. A trailing count "pill" is appended only when the
/// "Show number of items" preference ([categoryNumberOfItemsProvider]) is on
/// — the whole-library count with tabs on, or the per-category count with
/// tabs off.
class _LibraryTitle extends ConsumerWidget {
  const _LibraryTitle({required this.selectedCategoryId});

  final int selectedCategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTabs = ref.watch(categoryTabsProvider);
    final showCount = ref.watch(categoryNumberOfItemsProvider);
    final theme = Theme.of(context);

    return StreamBuilder<List<LibraryItem>>(
      stream: ref.watch(libraryRepositoryProvider).watchAll(),
      builder: (context, snap) {
        final items = snap.data ?? const <LibraryItem>[];

        if (showTabs) {
          // Tabs on: title is "Library"; count (if shown) is the whole-
          // library favourites size.
          return _titleRow(theme, 'Library', showCount ? items.length : null);
        }
        // Tabs off: title is the active category name; count (if shown) is
        // that category's size. Resolve the name asynchronously without
        // blocking the title.
        final count = showCount
            ? items.where((it) => it.inCategory(selectedCategoryId)).length
            : null;
        return FutureBuilder<List<Category>>(
          future: ref.watch(categoryRepositoryProvider).getAll(),
          builder: (context, catSnap) {
            final categories = catSnap.data ?? const <Category>[];
            final match =
                categories.where((c) => c.id == selectedCategoryId);
            final name =
                selectedCategoryId == Category.uncategorizedId || match.isEmpty
                    ? 'Default'
                    : match.first.name;
            return _titleRow(theme, name, count);
          },
        );
      },
    );
  }

  Widget _titleRow(ThemeData theme, String text, int? count) {
    if (count == null) return Text(text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Tabbed Filter / Sort / Display settings sheet for the library. Mirrors
/// Mihon's `LibrarySettingsDialog` (a TabbedDialog with three tabs). Every
/// change applies live: filter toggles flow back through [onFiltersChanged];
/// sort and display write straight to their providers — so there are no
/// Apply/Cancel buttons.
class _LibrarySettingsSheet extends ConsumerStatefulWidget {
  const _LibrarySettingsSheet({
    required this.current,
    required this.onFiltersChanged,
  });

  final LibraryFilters current;
  final ValueChanged<LibraryFilters> onFiltersChanged;

  @override
  ConsumerState<_LibrarySettingsSheet> createState() =>
      _LibrarySettingsSheetState();
}

class _LibrarySettingsSheetState extends ConsumerState<_LibrarySettingsSheet> {
  late LibraryFilters _draft = widget.current;

  void _set(LibraryFilters next) {
    setState(() => _draft = next);
    widget.onFiltersChanged(next);
  }

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

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.6;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Filter'),
                Tab(text: 'Sort'),
                Tab(text: 'Display'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildFilterTab(),
                  const _SortTab(),
                  const _DisplayTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab() {
    // Kotlin FilterPage order: Downloaded, Unread, Started, Bookmarked,
    // Completed, (interval custom — debug only, omitted), Tracked.
    return ListView(
      children: [
        _TriStateRow(
          label: 'Downloaded',
          state: _draft.downloaded,
          onTap: () =>
              _set(_draft.copyWith(downloaded: _cycle(_draft.downloaded))),
        ),
        _TriStateRow(
          label: 'Unread',
          state: _draft.unread,
          onTap: () => _set(_draft.copyWith(unread: _cycle(_draft.unread))),
        ),
        _TriStateRow(
          label: 'Started',
          state: _draft.started,
          onTap: () => _set(_draft.copyWith(started: _cycle(_draft.started))),
        ),
        _TriStateRow(
          label: 'Bookmarked',
          state: _draft.bookmarked,
          onTap: () =>
              _set(_draft.copyWith(bookmarked: _cycle(_draft.bookmarked))),
        ),
        _TriStateRow(
          label: 'Completed',
          state: _draft.completed,
          onTap: () =>
              _set(_draft.copyWith(completed: _cycle(_draft.completed))),
        ),
        _TriStateRow(
          label: 'Tracked',
          state: _draft.tracked,
          onTap: () => _set(_draft.copyWith(tracked: _cycle(_draft.tracked))),
        ),
      ],
    );
  }
}

/// A single tri-state filter row: a leading checkbox-style icon (blank →
/// included → excluded) and a label. Mirrors Mihon's `TriStateItem`.
class _TriStateRow extends StatelessWidget {
  const _TriStateRow({
    required this.label,
    required this.state,
    required this.onTap,
  });

  final String label;
  final TriState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData icon;
    switch (state) {
      case TriState.disabled:
        icon = Icons.check_box_outline_blank;
      case TriState.enabledIs:
        icon = Icons.check_box;
      case TriState.enabledNot:
        icon = Icons.disabled_by_default;
    }
    return ListTile(
      leading: Icon(
        icon,
        color: state == TriState.disabled ? null : theme.colorScheme.primary,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

/// Sort tab of the library settings sheet. Lists each sort axis with an
/// asc/desc arrow on the active one; tapping the active axis flips
/// direction, tapping another switches axes. Random sits last with a
/// Refresh icon and reshuffles each time it's (re-)selected. Mirrors
/// Mihon's `SortPage`.
class _SortTab extends ConsumerWidget {
  const _SortTab();

  static const _entries = <(LibrarySortAxis, String)>[
    (LibrarySortAxis.title, 'Alphabetically'),
    (LibrarySortAxis.totalChapters, 'Total chapters'),
    (LibrarySortAxis.lastRead, 'Last read'),
    (LibrarySortAxis.lastUpdate, 'Last update check'),
    (LibrarySortAxis.unread, 'Unread count'),
    (LibrarySortAxis.latestChapter, 'Latest chapter'),
    (LibrarySortAxis.chapterFetchDate, 'Chapter fetch date'),
    (LibrarySortAxis.dateAdded, 'Date added'),
    (LibrarySortAxis.random, 'Random'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(librarySortProvider);
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (final entry in _entries)
          ListTile(
            leading: Icon(
              entry.$1 == LibrarySortAxis.random
                  ? (entry.$1 == current.axis ? Icons.refresh : null)
                  : (entry.$1 == current.axis
                      ? (current.direction == LibrarySortDirection.ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                      : null),
              color:
                  entry.$1 == current.axis ? theme.colorScheme.primary : null,
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
              if (entry.$1 == LibrarySortAxis.random) {
                ref.read(randomSortSeedProvider.notifier).regenerate();
              }
            },
          ),
      ],
    );
  }
}

/// Display tab of the library settings sheet. Mirrors Mihon's `DisplayPage`:
/// a chip row of display modes, an "items per row" slider (grid modes only),
/// then Overlay and Tabs sections of checkbox toggles.
class _DisplayTab extends ConsumerWidget {
  const _DisplayTab();

  static const _modes = <(LibraryDisplayMode, String)>[
    (LibraryDisplayMode.compactGrid, 'Compact grid'),
    (LibraryDisplayMode.comfortableGrid, 'Comfortable grid'),
    (LibraryDisplayMode.coverOnlyGrid, 'Cover-only grid'),
    (LibraryDisplayMode.list, 'List'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryDisplayModeProvider);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final columns = isLandscape
        ? ref.watch(landscapeColumnsProvider)
        : ref.watch(portraitColumnsProvider);
    final columnsNotifier = isLandscape
        ? ref.read(landscapeColumnsProvider.notifier)
        : ref.read(portraitColumnsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _modes)
                FilterChip(
                  selected: mode == m.$1,
                  onSelected: (_) =>
                      ref.read(libraryDisplayModeProvider.notifier).setMode(m.$1),
                  label: Text(m.$2),
                ),
            ],
          ),
        ),
        if (mode != LibraryDisplayMode.list)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(child: Text('Items per row')),
                Text(columns > 0 ? '$columns' : 'Auto'),
              ],
            ),
          ),
        if (mode != LibraryDisplayMode.list)
          Slider(
            value: columns.toDouble().clamp(0, 10),
            min: 0,
            max: 10,
            divisions: 10,
            label: columns > 0 ? '$columns' : 'Auto',
            onChanged: (v) => columnsNotifier.setValue(v.round()),
          ),
        const _DisplayHeading('Overlay'),
        _CheckboxRow(
          label: 'Downloaded chapters',
          value: ref.watch(displayDownloadBadgeProvider),
          onChanged: (v) =>
              ref.read(displayDownloadBadgeProvider.notifier).setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Unread chapters',
          value: ref.watch(displayUnreadBadgeProvider),
          onChanged: (v) =>
              ref.read(displayUnreadBadgeProvider.notifier).setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Local source',
          value: ref.watch(displayLocalBadgeProvider),
          onChanged: (v) =>
              ref.read(displayLocalBadgeProvider.notifier).setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Language',
          value: ref.watch(displayLanguageBadgeProvider),
          onChanged: (v) =>
              ref.read(displayLanguageBadgeProvider.notifier).setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Continue reading button',
          value: ref.watch(showContinueReadingButtonProvider),
          onChanged: (v) => ref
              .read(showContinueReadingButtonProvider.notifier)
              .setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Most-read carousel',
          value: ref.watch(showMostReadCarouselProvider),
          onChanged: (v) =>
              ref.read(showMostReadCarouselProvider.notifier).setEnabled(v),
        ),
        const _DisplayHeading('Tabs'),
        _CheckboxRow(
          label: 'Show category tabs',
          value: ref.watch(categoryTabsProvider),
          onChanged: (v) =>
              ref.read(categoryTabsProvider.notifier).setEnabled(v),
        ),
        _CheckboxRow(
          label: 'Show number of items',
          value: ref.watch(categoryNumberOfItemsProvider),
          onChanged: (v) =>
              ref.read(categoryNumberOfItemsProvider.notifier).setEnabled(v),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}

/// Section heading inside the Display tab (e.g. "Overlay", "Tabs").
/// Mirrors Mihon's `HeadingItem`.
class _DisplayHeading extends StatelessWidget {
  const _DisplayHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A checkbox + label row used by the Display tab. Mirrors Mihon's
/// `CheckboxItem`.
class _CheckboxRow extends StatelessWidget {
  const _CheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

/// Result of the bulk remove dialog. Both flags are independent: the
/// user can opt to remove from library only, downloads only, or both.
/// `remove == false` means the user cancelled.
class _RemoveResult {
  const _RemoveResult({required this.remove, required this.deleteDownloads});
  final bool remove;
  final bool deleteDownloads;
}

/// Mihon-style `DeleteLibraryMangaDialog`: two checkboxes (manga from
/// library, downloaded chapters) wired to a single OK button that's
/// disabled until at least one box is ticked.
class _RemoveLibraryDialog extends StatefulWidget {
  const _RemoveLibraryDialog({required this.count});

  final int count;

  @override
  State<_RemoveLibraryDialog> createState() => _RemoveLibraryDialogState();
}

class _RemoveLibraryDialogState extends State<_RemoveLibraryDialog> {
  bool _removeFromLibrary = true;
  bool _deleteDownloads = false;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _removeFromLibrary || _deleteDownloads;
    return AlertDialog(
      title: Text('Remove ${widget.count} manga?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: _removeFromLibrary,
            onChanged: (v) => setState(() => _removeFromLibrary = v ?? false),
            title: const Text('Remove from library'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _deleteDownloads,
            onChanged: (v) => setState(() => _deleteDownloads = v ?? false),
            title: const Text('Delete downloaded chapters'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(
                    _RemoveResult(
                      remove: _removeFromLibrary,
                      deleteDownloads: _deleteDownloads,
                    ),
                  )
              : null,
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Auto-advancing horizontal pager of the user's top-progress favourites
/// (full cover backdrop, gradient, title, progress bar). Mirrors
/// Mihon's `LibraryMostReadCarousel` Compose widget. Tap a card → open
/// the manga details. Uses a virtually-infinite PageView so swipe loops
/// without snap; the dot indicator wraps to the real index.
class _MostReadCarousel extends StatefulWidget {
  const _MostReadCarousel({required this.items});

  final List<LibraryItem> items;

  @override
  State<_MostReadCarousel> createState() => _MostReadCarouselState();
}

class _MostReadCarouselState extends State<_MostReadCarousel> {
  static const Duration _autoAdvance = Duration(milliseconds: 4500);
  static const int _loopPages = 10000;

  late final int _startPage;
  late final PageController _controller;
  late int _currentPage;
  bool _userTouching = false;

  @override
  void initState() {
    super.initState();
    final count = widget.items.length;
    // Round the midpoint down to a multiple of count so dot index 0
    // matches items[0].
    _startPage = (_loopPages ~/ 2) - ((_loopPages ~/ 2) % count.clamp(1, _loopPages));
    _currentPage = _startPage;
    _controller = PageController(viewportFraction: 0.92, initialPage: _startPage);
    _scheduleAdvance();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleAdvance() {
    Future.delayed(_autoAdvance, () async {
      if (!mounted) return;
      if (!_userTouching && _controller.hasClients) {
        await _controller.animateToPage(
          _currentPage + 1,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      }
      _scheduleAdvance();
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    final activeIndex = _currentPage % count;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Most read',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          SizedBox(
            height: 200,
            child: Listener(
              onPointerDown: (_) => _userTouching = true,
              onPointerUp: (_) => _userTouching = false,
              onPointerCancel: (_) => _userTouching = false,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (page) =>
                    setState(() => _currentPage = page),
                itemCount: _loopPages,
                itemBuilder: (context, page) {
                  final item = widget.items[page % count];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _MostReadBannerCard(item: item),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == activeIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == activeIndex
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MostReadBannerCard extends ConsumerWidget {
  const _MostReadBannerCard({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = item.totalCount <= 0 ? 1 : item.totalCount;
    final ratio = (item.readCount / total).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final coverUrl = ref
        .watch(coverCacheProvider)
        .coverUrlFor(item.manga.id, item.manga.thumbnailUrl);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MangaDetailsScreen(mangaId: item.manga.id),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                SourceImage(
                  url: coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _) => ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                )
              else
                ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.manga.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 5,
                              color: Theme.of(context).colorScheme.primary,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            '$percent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
