// ===========================================================================
// Tide library.
//
// The shelf. Covers are the whole content, so the chrome gets out of their
// way: no app bar, no Material card, no popup menus — a header that names the
// category and counts it, category chips, and a grid of artwork on the ground.
//
// Every badge is drawn as glass over the cover rather than as a solid swatch
// from a colour scheme: unread takes the accent (it is the one number you are
// looking for), downloaded and Local/language sit back as quiet chips. The
// resume button is the same accent disc the series screen uses.
//
// All of the filter / sort / display / selection LOGIC below is untouched —
// this is a new presentation of it, not a new pipeline.
// ===========================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/base/base_preferences.dart';
import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
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
import '../../domain/manga/model/tri_state.dart';
import '../manga/manga_details_screen.dart';
import '../reader/reader_screen.dart';
import '../tide/tide.dart';

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
    Set<String>? downloadedKeys,
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
      final keys = downloadedKeys ?? const <String>{};
      final key = DownloadRepository.encodeMangaKey(
        item.manga.source,
        item.manga.id,
      );
      // Local manga count as downloaded (Kotlin: `manga.isLocal() ||
      // downloadCount > 0`).
      if (!applyTriState(
          downloaded, () => item.manga.source == 0 || keys.contains(key))) {
        return false;
      }
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

/// The shelf: streams the favorites + per-manga aggregate stats from
/// `libraryView`, partitions by category, and renders one of four display
/// modes (compact / comfortable / cover-only grids, or a list).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  LibraryFilters _filters = const LibraryFilters();

  // Created ONCE per consumer — previously each rebuild called watchAll()
  // inline (new stream → StreamBuilder resubscribe per setState, i.e. per
  // search keystroke / selection tap), and the title re-issued a fresh
  // categories query per rebuild.
  late final Stream<List<LibraryItem>> _libraryStream =
      ref.read(libraryRepositoryProvider).watchAll();
  late final Stream<List<Category>> _categoryStream =
      ref.read(categoryRepositoryProvider).watchAll();
  // Memoised downloaded/tracked filter sets (see build) — resolved once per
  // axis combination rather than on every rebuild.
  Future<_AsyncFilterSets>? _asyncSets;
  (bool, bool)? _asyncSetsKey;
  bool _searching = false;
  bool _updating = false;
  int _selectedCategoryId = Category.uncategorizedId;

  /// How far the masthead has folded away, 0–1. A [ValueNotifier] rather than
  /// screen state on purpose: the grid must not rebuild once per scrolled
  /// frame just so a title can shrink.
  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);

  /// Scroll distance over which the masthead folds. Roughly its own height —
  /// it should be gone by the time the first row of covers reaches the top.
  static const double _collapseDistance = 88;

  // Manga ids the user has multi-selected via long-press. Empty set
  // means selection mode is off.
  final Set<int> _selected = <int>{};
  late final TextEditingController _searchController = TextEditingController();

  // Ids of the entries currently visible in the grid (after category tab,
  // search and filter narrowing). Updated by [_LibraryBody] during its build
  // so "Select all" / "Invert selection" operate on the displayed set.
  List<int> _visibleIds = const <int>[];

  bool get _selecting => _selected.isNotEmpty;

  void _selectAllVisible() => setState(() => _selected.addAll(_visibleIds));

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

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchController.clear();
      _query = '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _collapse.dispose();
    super.dispose();
  }

  /// Vertical scrolling in the grid folds the masthead away. The category strip
  /// is a scrollable too and must not drive it, hence the axis test.
  bool _onScroll(ScrollNotification notification) =>
      _fold(notification.metrics);

  /// The grid can also change height without anyone scrolling — a search that
  /// narrows it to three results, a category with fewer entries than the one
  /// you left. Without this the masthead would stay folded away above a list
  /// that no longer scrolls, with no gesture left that could bring it back.
  bool _onScrollMetrics(ScrollMetricsNotification notification) =>
      _fold(notification.metrics);

  bool _fold(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return false;
    final next = (metrics.pixels / _collapseDistance).clamp(0.0, 1.0);
    if ((next - _collapse.value).abs() > 0.005) _collapse.value = next;
    return false;
  }

  /// Bulk download for selected manga: for each, fetch its chapters, sort
  /// by `sourceOrder` ascending (matches `_pickNextUnread`), take the
  /// first [count] unread (null = all) and enqueue each. Relies on
  /// `DownloadRepository.enqueue` being idempotent for already-queued or
  /// already-downloaded chapters.
  Future<void> _selectionDownloadNext(int? count) async {
    final toast = TideToast.of(context);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final downloadRepo = ref.read(downloadRepositoryProvider);
    final ids = _selected.toList(growable: false);
    var enqueued = 0;
    for (final id in ids) {
      final manga = await mangaRepo.getById(id);
      if (manga == null) continue;
      final chapters = await chapterRepo.getByMangaId(id);
      // Reading order = descending sourceOrder (0 == newest): "Next N
      // chapters" downloads the N OLDEST unread, not the N latest.
      final unread = chapters.where((c) => !c.read).toList()
        ..sort((a, b) => b.sourceOrder.compareTo(a.sourceOrder));
      final take = count == null ? unread : unread.take(count).toList();
      for (final c in take) {
        await downloadRepo.enqueue(manga, c);
        enqueued++;
      }
    }
    if (!mounted) return;
    _clearSelection();
    toast.show(enqueued == 0
        ? 'No unread chapters to download.'
        : 'Enqueued $enqueued chapter${enqueued == 1 ? '' : 's'}.');
  }

  Future<void> _openDownloadSheet() async {
    final picked = await showTideSheet<String>(
      context,
      (_) => const TideOptionSheet(
        title: 'Download chapters',
        options: [
          ('1', 'Next 1 chapter'),
          ('5', 'Next 5 chapters'),
          ('10', 'Next 10 chapters'),
          ('25', 'Next 25 chapters'),
          ('all', 'All unread chapters'),
        ],
        selected: '',
      ),
    );
    if (picked == null) return;
    await _selectionDownloadNext(picked == 'all' ? null : int.parse(picked));
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
    final toast = TideToast.of(context);
    final result = await showTideSheet<_RemoveResult>(
      context,
      (_) => _RemoveLibrarySheet(count: _selected.length),
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
    toast.show(msg);
  }

  Future<void> _selectionMoveToCategory() async {
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final allCats = await categoryRepo.getAll();
    final userCats =
        allCats.where((c) => !c.isSystemCategory).toList(growable: false);
    if (!mounted) return;
    if (userCats.isEmpty) {
      TideToast.of(context).show(
        'No categories yet. Create one in More → Categories first.',
      );
      return;
    }
    final selectedIds = await showTideSheet<Set<int>>(
      context,
      (_) => _BulkCategorySheet(categories: userCats),
    );
    if (selectedIds == null) return;
    final ids = _selected.toList(growable: false);
    for (final mangaId in ids) {
      await categoryRepo.setCategoriesForManga(mangaId, selectedIds);
    }
    if (!mounted) return;
    _clearSelection();
  }

  /// Filter / Sort / Display, behind one glass sheet. Every change applies
  /// live: filter toggles flow back through [_filters]; sort and display write
  /// straight to their providers — so there is nothing to apply or cancel.
  void _showSettingsSheet() {
    showTideSheet<void>(
      context,
      (_) => _LibrarySettingsSheet(
        current: _filters,
        onFiltersChanged: (next) => setState(() => _filters = next),
      ),
    );
  }

  /// "Open random entry": pick a random favourite from the active category
  /// (respecting the current search query) and open its details.
  Future<void> _openRandomEntry() async {
    final toast = TideToast.of(context);
    final navigator = Navigator.of(context);
    final items = await ref.read(libraryRepositoryProvider).watchAll().first;
    final inCategory = items
        .where((it) => it.inCategory(_selectedCategoryId))
        .toList(growable: false);
    final pool = inCategory.isEmpty ? items : inCategory;
    if (pool.isEmpty) {
      toast.show('No entries found.');
      return;
    }
    final pick = (pool.toList()..shuffle()).first;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(mangaId: pick.manga.id),
      ),
    );
  }

  Future<void> _openOverflow() async {
    final picked = await showTideSheet<String>(
      context,
      (_) => const TideOptionSheet(
        title: 'Library',
        options: [
          ('all', 'Update library'),
          ('category', 'Update this category'),
          ('random', 'Open random entry'),
        ],
        selected: '',
      ),
    );
    switch (picked) {
      case 'all':
        await _refreshLibrary();
      case 'category':
        await _refreshLibrary(categoryId: _selectedCategoryId);
      case 'random':
        await _openRandomEntry();
    }
  }

  /// Foreground library update. Independent of the workmanager schedule.
  /// When [categoryId] is non-null only manga belonging to that category
  /// are refreshed — used by the "Update this category" affordance.
  Future<void> _refreshLibrary({int? categoryId}) async {
    if (_updating) return;
    setState(() => _updating = true);
    final toast = TideToast.of(context);
    final notifications = NotificationService.instance;
    try {
      final updater = ref.read(libraryUpdaterProvider);
      // Mirror Mihon's foreground-update progress notification. Serialised:
      // onProgress fires from 5 concurrent sweep workers, and an unawaited
      // show landing after the final cancel left the notification stuck.
      var notifChain = Future<void>.value();
      void onProgress(LibraryUpdateProgress p) {
        notifChain = notifChain.then((_) {
          if (p.currentTitle == null) {
            return notifications.cancelLibraryProgress();
          }
          return notifications.showLibraryProgress(
            current: p.completed,
            total: p.total,
            title: p.currentTitle!,
          );
        });
      }

      final result = categoryId == null
          ? await updater.updateAll(onProgress: onProgress)
          : await updater.updateCategory(categoryId, onProgress: onProgress);
      await notifChain;
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
      toast.show(msg);
    } catch (e) {
      await notifications.cancelLibraryProgress();
      if (!mounted) return;
      toast.show('Refresh failed: $e');
    } finally {
      // New chapters may have been auto-downloaded — let the memoised
      // downloaded/tracked filter sets re-resolve on the next build.
      _asyncSets = null;
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayMode = ref.watch(libraryDisplayModeProvider);
    final sortPref = ref.watch(librarySortProvider);
    // "Downloaded only" mode forces the downloaded filter on (Kotlin
    // LibraryScreenModel: globalFilterDownloaded → ENABLED_IS) while leaving
    // the user's own filter selection untouched underneath.
    final effectiveFilters = ref.watch(downloadedOnlyProvider)
        ? _filters.copyWith(downloaded: TriState.enabledIs)
        : _filters;

    return PopScope(
      // Back closes the in-flight thing first: selection, then search.
      canPop: !_selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_searching) {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: TideColors.ground,
        body: Stack(
          children: [
            // The shelf shows a lot of ground between and behind its covers,
            // and at a quarter opacity the light behind it read as flat black
            // — the screen looked like the design's palette rather than the
            // design.
            const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.page)),
            Positioned.fill(
              child: TideRise(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    if (_searching) _searchField(),
                    Expanded(
                      child: NotificationListener<ScrollMetricsNotification>(
                        onNotification: _onScrollMetrics,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: _content(
                            displayMode,
                            sortPref,
                            effectiveFilters,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_selecting)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: _SelectionBar(
                  onCategory: _selectionMoveToCategory,
                  onMarkRead: () => _selectionMarkRead(true),
                  onMarkUnread: () => _selectionMarkRead(false),
                  onDownload: _openDownloadSheet,
                  onRemove: _selectionRemoveFromLibrary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    if (_selecting) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 12,
          20,
          12,
        ),
        child: Row(
          children: [
            TideIconButton(icon: Icons.close_rounded, onTap: _clearSelection),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                '${_selected.length} selected',
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                  color: TideColors.text,
                ),
              ),
            ),
            TideIconButton(icon: Icons.select_all, onTap: _selectAllVisible),
            const SizedBox(width: 9),
            TideIconButton(
              icon: Icons.flip_to_back,
              onTap: _invertVisibleSelection,
            ),
          ],
        ),
      );
    }
    // A masthead, not a toolbar. The shelf's name gets the display size the
    // rest of Tide gives a page's subject, with the state of the shelf as a
    // kicker over it — and it folds into the control row as you scroll, so the
    // covers get the screen back the moment you start reading the grid.
    //
    // The name is resolved ONCE and handed to both forms. Two independent
    // readers of the same library stream would be a second subscription for a
    // string, and would only work at all because the repository's stream
    // happens to be a broadcast one.
    return _LibraryHeading(
      selectedCategoryId: _selectedCategoryId,
      libraryStream: _libraryStream,
      categoryStream: _categoryStream,
      builder: (context, name, kicker) => Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12),
      child: ValueListenableBuilder<double>(
        valueListenable: _collapse,
        builder: (context, t, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
              child: Row(
                children: [
                  TideIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 15,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      // Held back until the masthead is nearly gone: the same
                      // name twice on one screen is the thing a collapsing
                      // header exists to avoid.
                      opacity: ((t - 0.62) / 0.38).clamp(0.0, 1.0),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.4,
                          color: TideColors.text,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TideIconButton(
                    icon: _searching ? Icons.close_rounded : Icons.search,
                    onTap: () => setState(() {
                      if (_searching) {
                        _closeSearch();
                      } else {
                        _searching = true;
                      }
                    }),
                  ),
                  const SizedBox(width: 9),
                  _FilterButton(
                    active: _filters.isActive,
                    onTap: _showSettingsSheet,
                  ),
                  const SizedBox(width: 9),
                  _OverflowButton(updating: _updating, onTap: _openOverflow),
                ],
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: 1 - t,
                child: Opacity(
                  // Fades out ahead of the fold so the last thing to go is
                  // empty space rather than half a letterform.
                  opacity: (1 - t * 1.5).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          kicker,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.kicker(
                            size: 11,
                            color: TideColors.accent,
                          ).copyWith(letterSpacing: 2.0),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.display(32),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(
        height: 42,
        child: TideGlass(
          radius: 21,
          tintTop: 0.09,
          tintBottom: 0.03,
          highlight: 0.16,
          border: 0.11,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Icon(Icons.search, size: 17, color: TideColors.textAt(0.42)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  cursorColor: TideColors.accent,
                  style: TideText.title(size: 14.5),
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    hintText: 'Search library',
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
    );
  }

  Widget _content(
    LibraryDisplayMode displayMode,
    LibrarySortPref sortPref,
    LibraryFilters effectiveFilters,
  ) {
    return StreamBuilder<List<LibraryItem>>(
      stream: _libraryStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorView(error: snapshot.error!);
        if (!snapshot.hasData) {
          return const Center(child: TideSpinner());
        }
        final items = snapshot.data!;
        if (items.isEmpty) return const _EmptyLibrary();
        return StreamBuilder<List<Category>>(
          stream: _categoryStream,
          builder: (context, catSnap) {
            final categories = catSnap.data ?? const <Category>[];
            // Both the Downloaded and Tracked axes need async-resolved sets.
            // Resolve them in parallel only when at least one is enabled —
            // most users never enable either.
            final needsDownloaded =
                effectiveFilters.downloaded != TriState.disabled;
            final needsTracked = effectiveFilters.tracked != TriState.disabled;
            if (needsDownloaded || needsTracked) {
              final downloadRepo = ref.watch(downloadRepositoryProvider);
              final trackRepo = ref.watch(trackRepositoryProvider);
              // Memoised: re-resolving on every rebuild walked the whole
              // downloads tree per frame while a downloaded/tracked filter
              // was active.
              final setsKey = (needsDownloaded, needsTracked);
              if (_asyncSets == null || _asyncSetsKey != setsKey) {
                _asyncSetsKey = setsKey;
                _asyncSets = _resolveAsyncFilterSets(
                  downloadRepo: needsDownloaded ? downloadRepo : null,
                  trackRepo: needsTracked ? trackRepo : null,
                );
              }
              return FutureBuilder<_AsyncFilterSets>(
                future: _asyncSets,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: TideSpinner());
                  }
                  return _body(
                    items,
                    categories,
                    sortPref,
                    effectiveFilters,
                    displayMode,
                    snap.data!.downloadedKeys,
                    snap.data!.trackedMangaIds,
                  );
                },
              );
            }
            return _body(
              items,
              categories,
              sortPref,
              effectiveFilters,
              displayMode,
              null,
              null,
            );
          },
        );
      },
    );
  }

  Widget _body(
    List<LibraryItem> items,
    List<Category> categories,
    LibrarySortPref sortPref,
    LibraryFilters filters,
    LibraryDisplayMode displayMode,
    Set<String>? downloadedKeys,
    Set<int>? trackedMangaIds,
  ) {
    return _LibraryBody(
      items: items,
      categories: categories,
      query: _query,
      sort: sortPref,
      filters: filters,
      downloadedKeys: downloadedKeys,
      trackedMangaIds: trackedMangaIds,
      displayMode: displayMode,
      selectedCategoryId: _selectedCategoryId,
      onCategoryChanged: (id) => setState(() => _selectedCategoryId = id),
      onRefresh: _refreshLibrary,
      selected: _selected,
      selecting: _selecting,
      onToggleSelected: _toggleSelected,
      onVisibleIdsResolved: (ids) => _visibleIds = ids,
    );
  }
}

/// Filter control — lights when any axis is set.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: TideGlass(
        radius: 20,
        tintTop: active ? 0.14 : 0.09,
        tintBottom: active ? 0.05 : 0.03,
        highlight: active ? 0.24 : 0.16,
        border: active ? 0.22 : 0.11,
        onTap: onTap,
        child: Center(
          child: Icon(
            Icons.filter_list,
            size: 17,
            color: active ? TideColors.accent : TideColors.textAt(0.8),
          ),
        ),
      ),
    );
  }
}

/// Library actions — spins while a foreground update runs.
class _OverflowButton extends StatelessWidget {
  const _OverflowButton({required this.updating, required this.onTap});

  final bool updating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: TideGlass(
        radius: 20,
        tintTop: updating ? 0.14 : 0.09,
        tintBottom: updating ? 0.05 : 0.03,
        highlight: updating ? 0.24 : 0.16,
        border: updating ? 0.22 : 0.11,
        onTap: updating ? null : onTap,
        child: Center(
          child: updating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: TideSpinner(size: 16, strokeWidth: 2),
                )
              : Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: TideColors.textAt(0.8),
                ),
        ),
      ),
    );
  }
}

/// Bulk actions over the current selection. Mirrors Mihon's
/// `LibraryBottomActionMenu`.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.onCategory,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onDownload,
    required this.onRemove,
  });

  final VoidCallback onCategory;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: TideGlass(
        radius: 29,
        blur: true,
        tintTop: 0.13,
        tintBottom: 0.05,
        highlight: 0.26,
        border: 0.15,
        saturation: 1.9,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarAction(
              icon: Icons.label_outline,
              label: 'Category',
              onTap: onCategory,
            ),
            _BarAction(icon: Icons.done_all, label: 'Read', onTap: onMarkRead),
            _BarAction(
              icon: Icons.remove_done,
              label: 'Unread',
              onTap: onMarkUnread,
            ),
            _BarAction(
              icon: Icons.download_outlined,
              label: 'Download',
              onTap: onDownload,
            ),
            _BarAction(
              icon: Icons.delete_outline,
              label: 'Remove',
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: TideColors.textAt(0.85)),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TideText.caption(size: 9.5, opacity: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the async-resolved sets that the filter predicate needs when
/// either the Downloaded or Tracked axis is active. Either field may be
/// null if its corresponding axis was disabled at resolve time.
class _AsyncFilterSets {
  const _AsyncFilterSets({this.downloadedKeys, this.trackedMangaIds});
  final Set<String>? downloadedKeys;
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
    trackedMangaIds: tracks == null ? null : {for (final t in tracks) t.mangaId},
  );
}

/// Resolves the next unread chapter for [mangaId] and opens the reader on
/// it, mirroring Mihon's library continue-reading button.
Future<void> _resumeNextUnread(
  BuildContext context,
  WidgetRef ref,
  int mangaId,
) async {
  final toast = TideToast.of(context);
  final navigator = Navigator.of(context);
  final chapters =
      await ref.read(chapterRepositoryProvider).getByMangaId(mangaId);
  // sourceOrder 0 == NEWEST, so reading order is descending sourceOrder —
  // resume must open the OLDEST unread chapter (matches the details
  // screen's _pickNextUnread), not the latest release.
  final unread = chapters.where((c) => !c.read).toList()
    ..sort((a, b) => b.sourceOrder.compareTo(a.sourceOrder));
  if (unread.isEmpty) {
    toast.show('No unread chapters left.');
    return;
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(mangaId: mangaId, chapterId: unread.first.id),
    ),
  );
}

class _LibraryBody extends ConsumerStatefulWidget {
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
  final Set<String>? downloadedKeys;
  final Set<int>? trackedMangaIds;
  final LibraryDisplayMode displayMode;
  final int selectedCategoryId;
  final ValueChanged<int> onCategoryChanged;
  final Future<void> Function() onRefresh;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  /// Reports the ids currently shown in the grid (post category/search/filter
  /// narrowing) so the header's Select-all / Invert actions act on them.
  final ValueChanged<List<int>> onVisibleIdsResolved;

  @override
  ConsumerState<_LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends ConsumerState<_LibraryBody> {
  // Memoised derived state: the parent setStates on every selection tap /
  // search keystroke / update spinner tick, and re-filtering + re-sorting the
  // whole library per rebuild was the dominant per-frame cost.
  Object? _bucketsKey;
  List<Category> _visibleCategories = const [];
  List<int> _tabIds = const [];
  Map<int, int>? _categoryCounts;

  Object? _pipelineKey;
  List<LibraryItem> _sorted = const [];
  List<int> _visibleIds = const [];

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final categories = widget.categories;
    final query = widget.query;
    final sort = widget.sort;
    final filters = widget.filters;

    // Determine which categories actually contain at least one item; we
    // only show chips when there's something to switch between.
    final bucketsKey = (items, categories);
    if (bucketsKey != _bucketsKey) {
      final usedIds = <int>{};
      for (final item in items) {
        usedIds.addAll(item.categoryIds);
      }
      // Filter the user-defined categories down to those with items. The
      // system "uncategorized" (id=0) is added as its own chip below, so it
      // must be excluded here — the DB seeds a real id-0 row and keeping it
      // produced a duplicate "Default" chip.
      final visibleCategories = [
        for (final c in categories)
          if (!c.isSystemCategory && usedIds.contains(c.id)) c,
      ]..sort((a, b) => a.order.compareTo(b.order));
      final hasUncategorized = usedIds.contains(Category.uncategorizedId);
      _visibleCategories = visibleCategories;
      _tabIds = <int>[
        if (hasUncategorized) Category.uncategorizedId,
        ...visibleCategories.map((c) => c.id),
      ];
      _categoryCounts = null;
      _bucketsKey = bucketsKey;
    }
    final tabIds = _tabIds;
    final visibleCategories = _visibleCategories;

    // Chips follow Mihon's `showPageTabs`: shown when the "Show category tabs"
    // pref is on OR a search is active — but still hidden when there's only
    // one effective bucket to switch between.
    final searching = query.isNotEmpty;
    final showCategoryTabsPref = ref.watch(categoryTabsProvider);
    final showCount = ref.watch(categoryNumberOfItemsProvider) || searching;
    final showTabs = (showCategoryTabsPref || searching) && tabIds.length > 1;

    // Pick the active id. Default to the first available chip if the
    // currently-selected one disappeared.
    final activeId = showTabs && !tabIds.contains(widget.selectedCategoryId)
        ? tabIds.first
        : widget.selectedCategoryId;

    // Random sort shuffles deterministically against the persisted seed
    // (regenerated whenever the user re-picks Random); every other axis uses
    // the comparator.
    final randomSeed = sort.axis == LibrarySortAxis.random
        ? ref.watch(randomSortSeedProvider)
        : 0;

    final pipelineKey = (
      items,
      query,
      sort.axis,
      sort.direction,
      randomSeed,
      filters.unread,
      filters.started,
      filters.bookmarked,
      filters.completed,
      filters.downloaded,
      filters.tracked,
      widget.downloadedKeys,
      widget.trackedMangaIds,
      showTabs ? activeId : null,
    );
    if (pipelineKey != _pipelineKey) {
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
                    downloadedKeys: widget.downloadedKeys,
                    trackedMangaIds: widget.trackedMangaIds,
                  ))
              .toList(growable: false)
          : filteredByQuery;

      _sorted = sort.axis == LibrarySortAxis.random
          ? ([...filtered]..shuffle(math.Random(randomSeed)))
          : ([...filtered]..sort(_compare(sort)));
      _visibleIds = _sorted.map((it) => it.manga.id).toList(growable: false);
      _pipelineKey = pipelineKey;
    }
    final sorted = _sorted;

    // Surface the visible ids so the header's Select-all / Invert act on the
    // displayed set. Pure assignment in the parent (no setState), so it's safe
    // to call during build.
    widget.onVisibleIdsResolved(_visibleIds);

    return Column(
      children: [
        if (showTabs)
          _CategoryChips(
            tabIds: tabIds,
            categories: visibleCategories,
            activeId: activeId,
            showCount: showCount,
            // Counted once per items emission (lazily, only while chips show
            // counts) instead of a where().length walk per chip per rebuild.
            countFor: (id) => (_categoryCounts ??= {
                  for (final tabId in tabIds)
                    tabId: items.where((it) => it.inCategory(tabId)).length,
                })[id] ??
                0,
            onTabSelected: widget.onCategoryChanged,
          ),
        Expanded(
          child: sorted.isEmpty
              ? _EmptyMatches(query: query)
              : TideRefresh(
                  onRefresh: widget.onRefresh,
                  child: _LibraryGrid(
                    items: sorted,
                    displayMode: widget.displayMode,
                    // orientationOf, not MediaQuery.of: the latter subscribes
                    // to every media-query aspect, so the whole grid rebuilt
                    // per frame of the keyboard-inset animation when library
                    // search focused.
                    columns: MediaQuery.orientationOf(context) ==
                            Orientation.landscape
                        ? ref.watch(landscapeColumnsProvider)
                        : ref.watch(portraitColumnsProvider),
                    selected: widget.selected,
                    selecting: widget.selecting,
                    onToggleSelected: widget.onToggleSelected,
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
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
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: tabIds.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = tabIds[i];
          final label =
              showCount ? '${_labelFor(id)} · ${countFor(id)}' : _labelFor(id);
          return Center(
            child: TideChip(
              label: label,
              selected: id == activeId,
              onTap: () => onTabSelected(id),
            ),
          );
        },
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
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 108),
        itemCount: items.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MangaRow(
            item: items[i],
            isSelected: selected.contains(items[i].manga.id),
            selecting: selecting,
            onToggleSelected: onToggleSelected,
          ),
        ),
      );
    }
    // Cover-only fits more per row because there's no title row eating
    // space below the cover.
    final maxExtent =
        displayMode == LibraryDisplayMode.coverOnlyGrid ? 124.0 : 146.0;
    final aspectRatio =
        displayMode == LibraryDisplayMode.comfortableGrid ? 0.56 : 0.66;
    // 0 columns = Auto: fall back to a max-extent delegate that picks the
    // column count from the cover width. A fixed count honours the user's
    // "Items per row" slider.
    final gridDelegate = columns > 0
        ? SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          )
        : SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
          );
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 108),
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

/// Downloaded counts for EVERY manga from ONE downloads-tree walk, shared by
/// all badges and refreshed when a download completes or is deleted.
final _downloadedCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final repo = ref.watch(downloadRepositoryProvider);
  // Coalesce bursts: a bulk download completes chapters back-to-back, and an
  // invalidation per event would re-walk the whole downloads tree each time.
  // One armed timer per burst caps the walks at ~1/s; badge lag is ≤1 s.
  Timer? scheduled;
  final sub = repo.events.listen((e) {
    if (e.state == DownloadState.completed ||
        e.state == DownloadState.deleted) {
      scheduled ??= Timer(const Duration(seconds: 1), () {
        scheduled = null;
        ref.invalidateSelf();
      });
    }
  });
  ref.onDispose(() {
    scheduled?.cancel();
    sub.cancel();
  });
  return repo.downloadedCountsByManga();
});

/// Downloaded-chapter-count badge — pure lookup into the shared counts map,
/// no per-card I/O.
class _DownloadCountBadge extends ConsumerWidget {
  const _DownloadCountBadge({required this.sourceId, required this.mangaId});

  final int sourceId;
  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(_downloadedCountsProvider).valueOrNull;
    final count =
        counts?[DownloadRepository.encodeMangaKey(sourceId, mangaId)] ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return _QuietBadge(text: '$count', icon: Icons.download_done_rounded);
  }
}

/// Reads the badge/overlay display preferences once for a cell.
({
  bool unread,
  bool download,
  bool local,
  bool language,
  bool resume,
}) _badgePrefs(WidgetRef ref) => (
      unread: ref.watch(displayUnreadBadgeProvider),
      download: ref.watch(displayDownloadBadgeProvider),
      local: ref.watch(displayLocalBadgeProvider),
      language: ref.watch(displayLanguageBadgeProvider),
      resume: ref.watch(showContinueReadingButtonProvider),
    );

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
    final overlayTitle = displayMode == LibraryDisplayMode.compactGrid;
    final titleBelow = displayMode == LibraryDisplayMode.comfortableGrid;
    final prefs = _badgePrefs(ref);
    final isLocal = manga.source == LocalSource.numericId;
    final sourceLangs = prefs.language
        ? ref.watch(installedSourceLangsProvider).valueOrNull
        : null;
    final lang =
        (sourceLangs != null && !isLocal) ? sourceLangs[manga.source] : null;

    final cover = Container(
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
      // Set into glass rather than laid on the ground: the same top-lit bevel
      // every pane in the app has, so a cover belongs to the surface instead
      // of being a photograph dropped onto it.
      child: TideEdge(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              TideCover(manga: manga),
              if (overlayTitle) ...[
                const Positioned.fill(child: TideScrim()),
                Positioned(
                  left: 8,
                  // Clear of the resume disc when one is showing — the title
                  // used to run underneath it.
                  right: prefs.resume && !selecting && item.unreadCount > 0
                      ? 48
                      : 8,
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
              // Top-start: unread is the number you are looking for, so it
              // takes the accent; Local / language sit back beneath it.
              Positioned(
                top: 7,
                left: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (prefs.unread && item.unreadCount > 0)
                      _UnreadBadge(count: item.unreadCount),
                    if (prefs.local && isLocal) ...[
                      const SizedBox(height: 4),
                      const _QuietBadge(text: 'LOCAL'),
                    ],
                    if (lang != null && lang.isNotEmpty && lang != 'all') ...[
                      const SizedBox(height: 4),
                      _QuietBadge(text: lang.toUpperCase()),
                    ],
                  ],
                ),
              ),
              if (prefs.download)
                Positioned(
                  top: 7,
                  right: 7,
                  child: _DownloadCountBadge(
                    sourceId: manga.source,
                    mangaId: manga.id,
                  ),
                ),
              if (prefs.resume && !selecting && item.unreadCount > 0)
                Positioned(
                  right: 7,
                  bottom: 7,
                  child: _ResumeButton(
                    onTap: () => _resumeNextUnread(context, ref, manga.id),
                  ),
                ),
              if (isSelected)
                Positioned.fill(
                  child: ColoredBox(
                    color: TideColors.accent.withValues(alpha: 0.22),
                    child: const Center(child: _SelectMark(selected: true)),
                  ),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => selecting
                      ? onToggleSelected(manga.id)
                      : _open(context),
                  onLongPress: () => onToggleSelected(manga.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final lit = isSelected
        ? Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: TideColors.accent.withValues(alpha: 0.9),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: TideColors.accent.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: cover,
          )
        : cover;

    if (!titleBelow) return lit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: lit),
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
}

/// Single row for `LibraryDisplayMode.list`.
class _MangaRow extends ConsumerWidget {
  const _MangaRow({
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
    final prefs = _badgePrefs(ref);
    final isLocal = manga.source == LocalSource.numericId;
    final sourceLangs = prefs.language
        ? ref.watch(installedSourceLangsProvider).valueOrNull
        : null;
    final lang =
        (sourceLangs != null && !isLocal) ? sourceLangs[manga.source] : null;

    return TideGlass(
      radius: 16,
      tintTop: isSelected ? 0.16 : 0.075,
      tintBottom: isSelected ? 0.05 : 0.026,
      highlight: isSelected ? 0.20 : 0.14,
      border: isSelected ? 0.30 : 0.09,
      onTap: () =>
          selecting ? onToggleSelected(manga.id) : _openDetails(context),
      padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => onToggleSelected(manga.id),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TideCover(manga: manga, cacheWidth: 180),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.title(),
                  ),
                  if (manga.author != null && manga.author!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      manga.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TideText.caption(),
                    ),
                  ],
                ],
              ),
            ),
            if (prefs.local && isLocal) ...[
              const SizedBox(width: 6),
              const _QuietBadge(text: 'LOCAL'),
            ],
            if (lang != null && lang.isNotEmpty && lang != 'all') ...[
              const SizedBox(width: 6),
              _QuietBadge(text: lang.toUpperCase()),
            ],
            if (prefs.download) ...[
              const SizedBox(width: 6),
              _DownloadCountBadge(sourceId: manga.source, mangaId: manga.id),
            ],
            if (prefs.unread && item.unreadCount > 0) ...[
              const SizedBox(width: 6),
              _UnreadBadge(count: item.unreadCount),
            ],
            if (prefs.resume && !selecting && item.unreadCount > 0) ...[
              const SizedBox(width: 8),
              _ResumeButton(
                size: 30,
                onTap: () => _resumeNextUnread(context, ref, manga.id),
              ),
            ],
            if (selecting) ...[
              const SizedBox(width: 8),
              _SelectMark(selected: isSelected),
            ],
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(mangaId: item.manga.id),
        ),
      );
}

/// Unread count — the accent filling a small shape, which is the one thing
/// Nocturne lets it fill.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: TideColors.accent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: TideColors.accent.withValues(alpha: 0.5),
            blurRadius: 12,
          ),
        ],
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: TideColors.ground,
        ),
      ),
    );
  }
}

/// Everything that is a fact rather than the headline number: downloaded
/// count, Local, language. Glass, so it sits back from the accent badge.
class _QuietBadge extends StatelessWidget {
  const _QuietBadge({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: TideColors.textAt(0.75)),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w500,
              color: TideColors.textAt(0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resume — the same accent disc the series screen's Continue bar uses.
class _ResumeButton extends StatelessWidget {
  const _ResumeButton({required this.onTap, this.size = 34});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TideColors.accent,
          boxShadow: [
            BoxShadow(
              color: TideColors.accent.withValues(alpha: 0.5),
              blurRadius: 16,
            ),
          ],
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          size: size * 0.62,
          color: const Color(0xFF12141F),
        ),
      ),
    );
  }
}

class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: tideEase,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color:
            selected ? TideColors.accent : Colors.white.withValues(alpha: 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? TideColors.accent
              : Colors.white.withValues(alpha: 0.28),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: TideColors.accent.withValues(alpha: 0.5),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: TideColors.ground)
          : null,
    );
  }
}

/// Bulk "Move to category". Returns the set of category ids the user picked
/// (empty Set means "no categories" — the manga ends up in Uncategorized).
/// Cancel returns null so the caller leaves memberships untouched.
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
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Move to category', style: TideText.display(21)),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, c) in widget.categories.indexed) ...[
                    if (i > 0) const SizedBox(height: 10),
                    TideCheck(
                      label: c.name,
                      value: _picked.contains(c.id),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _picked.add(c.id);
                        } else {
                          _picked.remove(c.id);
                        }
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TideButton(
                  label: 'Save',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(_picked),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const TideEmpty(
        title: 'Your library is empty',
        message: 'Find something on Browse and add it, and it will live here.',
      );
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return TideEmpty(
      title: query.isEmpty ? 'Nothing here' : 'No matches',
      message: query.isEmpty
          ? 'This category has no entries, or your filters have narrowed them '
              'all away.'
          : 'Nothing in your library matches "$query".',
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return TideEmpty(
      title: 'Could not open the library',
      message: '$error',
    );
  }
}

/// Resolves what the head of the library should say — the shelf's name and the
/// kicker stating what is on it — and hands both to [builder].
///
/// A builder rather than two widgets because the masthead and the compact line
/// that replaces it live in different places in the header, and each opening
/// its own [StreamBuilder] would be a second subscription to the library for
/// the sake of a string. It would also only work at all because the
/// repository's stream happens to be broadcast.
class _LibraryHeading extends ConsumerWidget {
  const _LibraryHeading({
    required this.selectedCategoryId,
    required this.libraryStream,
    required this.categoryStream,
    required this.builder,
  });

  final int selectedCategoryId;

  /// The screen's shared streams — the heading must NOT open its own
  /// `watchAll()` (a second live library query) or re-issue a categories
  /// fetch per rebuild, as it used to.
  final Stream<List<LibraryItem>> libraryStream;
  final Stream<List<Category>> categoryStream;

  final Widget Function(BuildContext context, String name, String kicker)
      builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTabs = ref.watch(categoryTabsProvider);
    final showCount = ref.watch(categoryNumberOfItemsProvider);

    return StreamBuilder<List<LibraryItem>>(
      stream: libraryStream,
      builder: (context, snap) {
        final items = snap.data ?? const <LibraryItem>[];
        if (showTabs) {
          return builder(context, 'Library', kickerFor(items, showCount));
        }
        // Without chips the header IS the category indicator, so it has to
        // narrow the stats to that category too.
        final scoped = items
            .where((it) => it.inCategory(selectedCategoryId))
            .toList(growable: false);
        return StreamBuilder<List<Category>>(
          stream: categoryStream,
          builder: (context, catSnap) {
            final categories = catSnap.data ?? const <Category>[];
            final match = categories.where((c) => c.id == selectedCategoryId);
            final name =
                selectedCategoryId == Category.uncategorizedId || match.isEmpty
                    ? 'Default'
                    : match.first.name;
            return builder(context, name, kickerFor(scoped, showCount));
          },
        );
      },
    );
  }

  /// What is actually on the shelf, in the design's eyebrow voice.
  ///
  /// The entry count is gated on Mihon's "Show number of items" preference,
  /// which is what that preference means. The unread total is not covered by
  /// it — it's the number this screen is really about — so it stands on its
  /// own, and when there is nothing waiting the line says so rather than
  /// leaving a gap where a fact should be.
  static String kickerFor(List<LibraryItem> scope, bool showCount) {
    if (scope.isEmpty) return 'NOTHING HERE YET';
    var unread = 0;
    for (final item in scope) {
      unread += item.unreadCount;
    }
    final parts = <String>[
      if (showCount) '${scope.length} ${scope.length == 1 ? 'ENTRY' : 'ENTRIES'}',
      if (unread > 0) '$unread UNREAD',
    ];
    return parts.isEmpty ? 'ALL CAUGHT UP' : parts.join(' · ');
  }
}

/// Filter / Sort / Display behind one glass sheet, switched with the same
/// segmented control Browse uses. Every change applies live.
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
  int _view = 0;

  void _set(LibraryFilters next) {
    setState(() => _draft = next);
    widget.onFiltersChanged(next);
  }

  TriState _cycle(TriState v) => switch (v) {
        TriState.disabled => TriState.enabledIs,
        TriState.enabledIs => TriState.enabledNot,
        TriState.enabledNot => TriState.disabled,
      };

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideSegmented(
              labels: const ['Filter', 'Sort', 'Display'],
              index: _view,
              onChanged: (i) => setState(() => _view = i),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: switch (_view) {
                0 => _filterView(),
                1 => const _SortView(),
                _ => const _DisplayView(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterView() {
    // Kotlin FilterPage order: Downloaded, Unread, Started, Bookmarked,
    // Completed, Tracked. While "Downloaded only" mode is on, the Downloaded
    // row is pinned to enabled and locked.
    final downloadedOnly = ref.watch(downloadedOnlyProvider);
    final rows = <Widget>[
      _TriRow(
        label: 'Downloaded',
        state: downloadedOnly ? TriState.enabledIs : _draft.downloaded,
        locked: downloadedOnly,
        onTap: downloadedOnly
            ? null
            : () => _set(_draft.copyWith(downloaded: _cycle(_draft.downloaded))),
      ),
      _TriRow(
        label: 'Unread',
        state: _draft.unread,
        onTap: () => _set(_draft.copyWith(unread: _cycle(_draft.unread))),
      ),
      _TriRow(
        label: 'Started',
        state: _draft.started,
        onTap: () => _set(_draft.copyWith(started: _cycle(_draft.started))),
      ),
      _TriRow(
        label: 'Bookmarked',
        state: _draft.bookmarked,
        onTap: () =>
            _set(_draft.copyWith(bookmarked: _cycle(_draft.bookmarked))),
      ),
      _TriRow(
        label: 'Completed',
        state: _draft.completed,
        onTap: () => _set(_draft.copyWith(completed: _cycle(_draft.completed))),
      ),
      _TriRow(
        label: 'Tracked',
        state: _draft.tracked,
        onTap: () => _set(_draft.copyWith(tracked: _cycle(_draft.tracked))),
      ),
    ];
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => rows[i],
    );
  }
}

/// One tri-state axis, stated in words — three states behind one icon is a
/// puzzle the reader has to solve every time.
class _TriRow extends StatelessWidget {
  const _TriRow({
    required this.label,
    required this.state,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final TriState state;
  final VoidCallback? onTap;

  /// Pinned by "Downloaded only" mode — shown, but not changeable here.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final (icon, word) = switch (state) {
      TriState.disabled => (Icons.check_box_outline_blank, 'Off'),
      TriState.enabledIs => (Icons.check_box, 'Include'),
      TriState.enabledNot => (Icons.disabled_by_default, 'Exclude'),
    };
    final row = TideRow(
      icon: icon,
      title: label,
      subtitle: locked ? '$word · locked by Downloaded only' : word,
      lit: state != TriState.disabled,
      onTap: onTap,
    );
    return locked ? Opacity(opacity: 0.55, child: row) : row;
  }
}

/// Sort axes. Tapping the active one flips direction; tapping another
/// switches axis. Random reshuffles each time it is re-picked.
class _SortView extends ConsumerWidget {
  const _SortView();

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
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final (axis, label) = _entries[i];
        final active = axis == current.axis;
        final ascending = current.direction == LibrarySortDirection.ascending;
        return TideRow(
          icon: axis == LibrarySortAxis.random
              ? Icons.shuffle
              : active
                  ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.remove,
          title: label,
          subtitle: active && axis != LibrarySortAxis.random
              ? (ascending ? 'Ascending' : 'Descending')
              : null,
          lit: active,
          trailing: active
              ? const Icon(Icons.check_rounded,
                  size: 18, color: TideColors.accent)
              : null,
          onTap: () {
            ref.read(librarySortProvider.notifier).setAxis(axis);
            if (axis == LibrarySortAxis.random) {
              ref.read(randomSortSeedProvider.notifier).regenerate();
            }
          },
        );
      },
    );
  }
}

/// Display mode, density, and which overlays the covers carry.
class _DisplayView extends ConsumerWidget {
  const _DisplayView();

  static const _modes = <(LibraryDisplayMode, String)>[
    (LibraryDisplayMode.compactGrid, 'Compact'),
    (LibraryDisplayMode.comfortableGrid, 'Comfortable'),
    (LibraryDisplayMode.coverOnlyGrid, 'Cover only'),
    (LibraryDisplayMode.list, 'List'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryDisplayModeProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final columns = isLandscape
        ? ref.watch(landscapeColumnsProvider)
        : ref.watch(portraitColumnsProvider);
    final columnsNotifier = isLandscape
        ? ref.read(landscapeColumnsProvider.notifier)
        : ref.read(portraitColumnsProvider.notifier);

    return ListView(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (m, label) in _modes)
              TideChip(
                label: label,
                selected: mode == m,
                onTap: () =>
                    ref.read(libraryDisplayModeProvider.notifier).setMode(m),
              ),
          ],
        ),
        if (mode != LibraryDisplayMode.list) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Items per row',
                  style: TideText.title(size: 13.5),
                ),
              ),
              Text(
                columns > 0 ? '$columns' : 'Auto',
                style: TideText.title(size: 13.5, color: TideColors.accent),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: TideColors.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: TideColors.accentLight,
              overlayColor: TideColors.accent.withValues(alpha: 0.15),
              valueIndicatorColor: TideColors.accent,
              trackHeight: 3,
            ),
            child: Slider(
              value: columns.toDouble().clamp(0, 10),
              min: 0,
              max: 10,
              divisions: 10,
              label: columns > 0 ? '$columns' : 'Auto',
              onChanged: (v) => columnsNotifier.setValue(v.round()),
            ),
          ),
        ],
        const SizedBox(height: 6),
        const TideSectionHeader(
          label: 'On the cover',
          padding: EdgeInsets.fromLTRB(2, 8, 2, 12),
        ),
        _Toggle(
          label: 'Downloaded chapters',
          value: ref.watch(displayDownloadBadgeProvider),
          onChanged: (v) =>
              ref.read(displayDownloadBadgeProvider.notifier).setEnabled(v),
        ),
        _Toggle(
          label: 'Unread chapters',
          value: ref.watch(displayUnreadBadgeProvider),
          onChanged: (v) =>
              ref.read(displayUnreadBadgeProvider.notifier).setEnabled(v),
        ),
        _Toggle(
          label: 'Local source',
          value: ref.watch(displayLocalBadgeProvider),
          onChanged: (v) =>
              ref.read(displayLocalBadgeProvider.notifier).setEnabled(v),
        ),
        _Toggle(
          label: 'Language',
          value: ref.watch(displayLanguageBadgeProvider),
          onChanged: (v) =>
              ref.read(displayLanguageBadgeProvider.notifier).setEnabled(v),
        ),
        _Toggle(
          label: 'Resume button',
          value: ref.watch(showContinueReadingButtonProvider),
          onChanged: (v) =>
              ref.read(showContinueReadingButtonProvider.notifier).setEnabled(v),
        ),
        const TideSectionHeader(
          label: 'Categories',
          padding: EdgeInsets.fromLTRB(2, 22, 2, 12),
        ),
        _Toggle(
          label: 'Show category chips',
          value: ref.watch(categoryTabsProvider),
          onChanged: (v) =>
              ref.read(categoryTabsProvider.notifier).setEnabled(v),
        ),
        _Toggle(
          label: 'Show number of items',
          value: ref.watch(categoryNumberOfItemsProvider),
          onChanged: (v) =>
              ref.read(categoryNumberOfItemsProvider.notifier).setEnabled(v),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TideRow(
        icon: value ? Icons.visibility : Icons.visibility_off_outlined,
        title: label,
        lit: value,
        onTap: () => onChanged(!value),
        trailing: TideSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Result of the bulk remove sheet. Both flags are independent: the user can
/// opt to remove from library only, downloads only, or both.
class _RemoveResult {
  const _RemoveResult({required this.remove, required this.deleteDownloads});
  final bool remove;
  final bool deleteDownloads;
}

/// Mihon's `DeleteLibraryMangaDialog`: two independent checks wired to one
/// confirm that stays inert until at least one is ticked.
class _RemoveLibrarySheet extends StatefulWidget {
  const _RemoveLibrarySheet({required this.count});

  final int count;

  @override
  State<_RemoveLibrarySheet> createState() => _RemoveLibrarySheetState();
}

class _RemoveLibrarySheetState extends State<_RemoveLibrarySheet> {
  bool _removeFromLibrary = true;
  bool _deleteDownloads = false;

  @override
  Widget build(BuildContext context) {
    final canConfirm = _removeFromLibrary || _deleteDownloads;
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.count == 1 ? 'Remove 1 entry' : 'Remove ${widget.count} entries',
            style: TideText.display(21),
          ),
          const SizedBox(height: 18),
          TideCheck(
            label: 'Remove from library',
            value: _removeFromLibrary,
            onChanged: (v) => setState(() => _removeFromLibrary = v),
          ),
          const SizedBox(height: 14),
          TideCheck(
            label: 'Delete downloaded chapters',
            value: _deleteDownloads,
            onChanged: (v) => setState(() => _deleteDownloads = v),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: canConfirm ? 1 : 0.4,
                  child: TideButton(
                    label: 'Remove',
                    primary: true,
                    onTap: () {
                      if (!canConfirm) return;
                      Navigator.of(context).pop(
                        _RemoveResult(
                          remove: _removeFromLibrary,
                          deleteDownloads: _deleteDownloads,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
