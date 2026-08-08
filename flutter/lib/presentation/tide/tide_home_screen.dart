// ===========================================================================
// Tide home.
//
// The design's thesis, and the reason this is not another cover grid: a
// library app answers "what do I own", but following ongoing series only ever
// raises one question — what is next, and where was I. So the screen is
// ordered by reading position rather than by collection:
//
//   hero      the series you are furthest through, rotating through the top 5
//   continue  what you are mid-way into, with the position you left it at
//   tonight   everything that has arrived, newest first
//
// Tonight IS the updates surface — there is no separate Updates page. It
// carries the whole of it: the global refresh (button and pull-to-refresh),
// day grouping, the unread / bookmarked / muted-scanlator filters, search,
// multi-select with bulk mark-read and bookmark, and the route to Upcoming.
// The one thing it drops is a redundant day header over today's arrivals,
// because that is what the section is already called.
//
// Every section is fed by a repository stream the app already maintains, so
// this is a new presentation of existing state, not a new source of truth.
// ===========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/cover/cover_cache.dart';
import '../../data/history/history_repository.dart';
import '../../data/library/library_repository.dart';
import '../../data/library/library_updater.dart';
import '../../data/source/extension_repository.dart';
import '../../data/updates/updates_filter_prefs.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/chapter/service/set_read_status.dart';
import '../../domain/library/model/library_item.dart';
import '../../domain/manga/model/tri_state.dart';
import '../common/app_route_observer.dart';
import '../common/source_image.dart';
import '../home/home_screen.dart';
import '../reader/reader_screen.dart';
import '../upcoming/upcoming_screen.dart';
import 'tide.dart';
import '../manga/manga_details_screen.dart';
import '../util/timestamp_format.dart';
import '../util/user_message.dart';

/// One entry in the "Continue" rail: a library entry the reader is part-way
/// through, joined with the chapter history last touched it.
class _Resuming {
  const _Resuming({
    required this.item,
    required this.chapterLabel,
    required this.ratio,
    required this.readAt,
  });

  final LibraryItem item;
  final String chapterLabel;

  /// Fraction of the series read, 0–1 — what the card's underline shows.
  final double ratio;
  final DateTime readAt;
}

/// A row of the Tonight feed: either a day separator or an update.
sealed class _FeedRow {
  const _FeedRow();
}

class _DayRow extends _FeedRow {
  const _DayRow(this.label);
  final String label;
}

class _UpdateRow extends _FeedRow {
  const _UpdateRow(this.update);
  final LibraryUpdate update;
}

class TideHomeScreen extends ConsumerStatefulWidget {
  const TideHomeScreen({super.key});

  @override
  ConsumerState<TideHomeScreen> createState() => _TideHomeScreenState();
}

class _TideHomeScreenState extends ConsumerState<TideHomeScreen>
    with SuspendsWhileHidden {
  // Held rather than rebuilt per frame: a stream recreated inside build()
  // re-subscribes on every rebuild and the list flickers back to its loading
  // state. Same pattern the History screen uses.
  //
  // Nulled out while this screen is hidden — see [SuspendsWhileHidden]. Tide
  // is tab 0 AND the thing the reader is opened from, so it spends most of a
  // reading session invisible, and all three of these are invalidated by the
  // reader's own progress writes.
  Stream<List<LibraryItem>>? _library;
  Stream<List<HistoryWithContext>>? _history;
  Stream<List<LibraryUpdate>>? _updates;

  void _syncStreams() {
    _library =
        watching ? ref.read(libraryRepositoryProvider).watchAll() : null;
    _history =
        watching ? ref.read(historyRepositoryProvider).watchRecent() : null;
    _updates =
        watching ? ref.read(updatesRepositoryProvider).watchAll() : null;
  }

  @override
  void onWatchingChanged() => _syncStreams();

  final _scroll = ScrollController();

  /// Index of the hero currently shown; advanced on a timer.
  int _hero = 0;
  Timer? _rotate;

  /// Whether a foreground library update is in flight. Drives the header
  /// control's spinner and blocks a second concurrent run.
  bool _updating = false;

  /// Chapter ids picked in the Tonight feed's multi-select.
  final Set<int> _selected = <int>{};

  bool _searchingUpdates = false;
  String _updatesQuery = '';
  final TextEditingController _updatesSearch = TextEditingController();

  /// Memoised filter + day-grouping output for Tonight. Recomputed only when
  /// the stream emits, a filter axis or the query changes, or the calendar day
  /// rolls over — not on every selection tap or keystroke rebuild.
  Object? _rowsKey;
  List<LibraryUpdate> _visible = const [];
  List<_FeedRow> _rows = const [];

  /// Same memoisation for the two rails above the feed — keyed on the source
  /// lists themselves, which the streams replace only when the data changes.
  List<LibraryItem>? _railsItems;
  List<HistoryWithContext>? _railsHistory;
  List<LibraryItem> _heroes = const [];
  List<_Resuming> _resumingRail = const [];

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _syncStreams();
    _rotate = Timer.periodic(const Duration(seconds: 5), (_) {
      // Only advance while Tide is the visible tab — the banner rotating
      // behind another screen is work nobody sees.
      if (!mounted || ref.read(homeTabIndexProvider) != 0) return;
      setState(() => _hero++);
    });
    // Reselecting the tab returns to the top, matching the other tabs.
    ref.listenManual<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab != 0 || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: tideEase,
      );
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _scroll.dispose();
    _updatesSearch.dispose();
    super.dispose();
  }

  /// Top 5 by completion ratio, counting only entries actually started — the
  /// same "what are you working through" rule the library carousel uses.
  List<LibraryItem> _topRead(List<LibraryItem> items) {
    final started = items
        .where((it) => it.totalCount > 0 && it.readCount > 0)
        .toList();
    // Ratios tie constantly — every finished series is 1.0, and 10/20 and 5/10
    // are the same number — and Dart's `List.sort` is not stable, so without a
    // tie-break `take(5)` could hand back a DIFFERENT five between rebuilds
    // and the hero rail would change what it rotates through on its own.
    // Title, then id, so the answer is total.
    final ratio = {
      for (final it in started) it.manga.id: it.readCount / it.totalCount,
    };
    started.sort((a, b) {
      final byRatio = ratio[b.manga.id]!.compareTo(ratio[a.manga.id]!);
      if (byRatio != 0) return byRatio;
      final byTitle = a.manga.title
          .toLowerCase()
          .compareTo(b.manga.title.toLowerCase());
      return byTitle != 0 ? byTitle : a.manga.id.compareTo(b.manga.id);
    });
    return started.take(5).toList(growable: false);
  }

  /// History carries recency and the chapter you were on; the library view
  /// carries how far through the series that is. Joined on manga id, newest
  /// first, one row per series.
  List<_Resuming> _resuming(
    List<LibraryItem> items,
    List<HistoryWithContext> history,
  ) {
    final byId = {for (final it in items) it.manga.id: it};
    final seen = <int>{};
    final out = <_Resuming>[];
    for (final h in history) {
      final item = byId[h.mangaId];
      // Finished series stay out of the rail: there is nothing to continue.
      if (item == null || item.unreadCount == 0) continue;
      if (!seen.add(h.mangaId)) continue;
      out.add(_Resuming(
        item: item,
        chapterLabel: tideChapterLabel(h.chapterName, h.chapterNumber),
        ratio: item.totalCount == 0 ? 0 : item.readCount / item.totalCount,
        readAt: h.readAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      ));
      if (out.length >= 12) break;
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Updates: refresh, filtering, selection
  // -------------------------------------------------------------------------

  /// Foreground library update — the same `LibraryUpdater.updateAll` the
  /// Updates tab ran. The workmanager schedule keeps running independently in
  /// the background; this is the "do it now" path.
  Future<void> _refresh() async {
    if (_updating) return;
    setState(() => _updating = true);
    final toast = TideToast.of(context);
    try {
      final result = await ref.read(libraryUpdaterProvider).updateAll();
      if (!mounted) return;
      final msg = result.newChapters == 0
          ? 'No new chapters found.'
          : '${result.newChapters} new chapter'
              '${result.newChapters == 1 ? '' : 's'} added.';
      toast.show(msg);
    } catch (e) {
      if (!mounted) return;
      toast.show(userMessage(e, fallback: 'Couldn\'t refresh.'));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _toggleSelected(int chapterId) {
    setState(() {
      if (!_selected.add(chapterId)) _selected.remove(chapterId);
    });
    _syncBarSuppression();
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
    _syncBarSuppression();
  }

  /// The shell's navigation and this screen's bulk bar want the same strip of
  /// glass at the bottom edge; only one of them may have it.
  void _syncBarSuppression() {
    final suppress = _selected.isNotEmpty;
    if (ref.read(tideBarSuppressedProvider) != suppress) {
      ref.read(tideBarSuppressedProvider.notifier).state = suppress;
    }
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_visible.map((u) => u.chapterId));
    });
    _syncBarSuppression();
  }

  /// Toggles every visible row's membership — mirrors Kotlin
  /// `UpdatesScreenModel.invertSelection`.
  void _invertSelection() {
    setState(() {
      for (final u in _visible) {
        if (!_selected.add(u.chapterId)) _selected.remove(u.chapterId);
      }
    });
    _syncBarSuppression();
  }

  Future<void> _bulkSetRead(bool read) async {
    final repo = ref.read(chapterRepositoryProvider);
    final setReadStatus = ref.read(setReadStatusProvider);
    final selected = _visible
        .where((u) => _selected.contains(u.chapterId))
        .toList(growable: false);
    // The interactor needs whole `Chapter` rows (read/lastPageRead/bookmark
    // decide what to skip and which download to delete), so the picked ids
    // are resolved back — but only those. Reading each owning series in full
    // to sieve them out cost the length of the series, once per series
    // touched, for a selection that is usually a handful of rows.
    final picked = await repo.getByIds(selected.map((u) => u.chapterId));
    if (picked.isNotEmpty) {
      // Still grouped by manga: setRead is a per-series interactor.
      final byManga = <int, List<Chapter>>{};
      for (final c in picked) {
        (byManga[c.mangaId] ??= <Chapter>[]).add(c);
      }
      for (final chapters in byManga.values) {
        await setReadStatus.setRead(read: read, chapters: chapters);
      }
    }
    _clearSelection();
  }

  Future<void> _bulkSetBookmark(bool bookmark) async {
    final repo = ref.read(chapterRepositoryProvider);
    final ids = _visible
        .where((u) => _selected.contains(u.chapterId))
        .map((u) => u.chapterId)
        .toList(growable: false);
    await repo.setBookmarkForIds(ids, bookmark);
    _clearSelection();
  }

  void _openUpdatesSearch() => setState(() => _searchingUpdates = true);

  void _closeUpdatesSearch() {
    setState(() {
      _searchingUpdates = false;
      _updatesQuery = '';
      _updatesSearch.clear();
    });
  }

  Future<void> _openFilters() => showTideSheet<void>(
        context,
        (_) => const _UpdatesFilterSheet(),
      );

  // -------------------------------------------------------------------------

  Future<void> _openSeries(int mangaId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(mangaId: mangaId),
        ),
      );

  Future<void> _openChapter(int mangaId, int chapterId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(mangaId: mangaId, chapterId: chapterId),
        ),
      );

  /// Open the oldest unread chapter — reading order, not release order. Same
  /// resolution the library grid's resume affordance performs.
  Future<void> _resume(int mangaId) async {
    final toast = TideToast.of(context);
    final next = await ref.read(chapterRepositoryProvider).nextUnread(mangaId);
    if (!mounted) return;
    if (next == null) {
      toast.show('No unread chapters left.');
      return;
    }
    await _openChapter(mangaId, next.id);
  }

  @override
  Widget build(BuildContext context) {
    // The shell keeps every tab alive in an IndexedStack, so without this the
    // aurora, the hero's slow zoom and the Read button's sheen would go on
    // animating — and drawing — while the reader is on another tab entirely.
    // TickerMode parks them all whenever Tide isn't the visible tab.
    final visible = ref.watch(homeTabIndexProvider) == 0;
    return TickerMode(
      enabled: visible,
      // System back closes the in-flight thing first: selection, then search.
      child: PopScope(
        canPop: !_selecting && !_searchingUpdates,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) {
            _clearSelection();
          } else if (_searchingUpdates) {
            _closeUpdatesSearch();
          }
        },
        child: _scaffold(),
      ),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora()),
          Positioned.fill(
            child: StreamBuilder<List<LibraryItem>>(
                stream: _library,
                builder: (context, librarySnap) {
                  final items = librarySnap.data ?? const <LibraryItem>[];
                  return StreamBuilder<List<HistoryWithContext>>(
                    stream: _history,
                    builder: (context, historySnap) {
                      return StreamBuilder<List<LibraryUpdate>>(
                        stream: _updates,
                        builder: (context, updatesSnap) => _content(
                          items,
                          historySnap.data ?? const <HistoryWithContext>[],
                          updatesSnap.data ?? const <LibraryUpdate>[],
                          loading: !librarySnap.hasData,
                        ),
                      );
                    },
                  );
                },
          ),
          ),
          // The navigation itself lives in the shell now, over every tab.
          // What stays here is the bulk bar, which takes its place while a
          // selection is live.
          if (_selecting)
            Positioned(
              left: 16,
              right: 16,
              bottom: 26,
              child: _SelectionBar(
                selected: _visible
                    .where((u) => _selected.contains(u.chapterId))
                    .toList(growable: false),
                onBookmark: () => _bulkSetBookmark(true),
                onUnbookmark: () => _bulkSetBookmark(false),
                onMarkRead: () => _bulkSetRead(true),
                onMarkUnread: () => _bulkSetRead(false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(
    List<LibraryItem> items,
    List<HistoryWithContext> history,
    List<LibraryUpdate> updates, {
    required bool loading,
  }) {
    if (loading) {
      return const Center(
        child: TideSpinner(),
      );
    }
    // Memoised on the two lists' identity: the hero timer rebuilds this
    // screen every 5 seconds to advance the banner, and a sort of the whole
    // library plus a history join is not what advancing a banner should cost.
    if (!identical(items, _railsItems) || !identical(history, _railsHistory)) {
      _railsItems = items;
      _railsHistory = history;
      _heroes = _topRead(items);
      _resumingRail = _resuming(items, history);
    }
    final heroes = _heroes;
    final resuming = _resumingRail;
    final filters = ref.watch(updatesFiltersProvider);
    _recomputeRows(updates, filters);

    return TideRise(
      child: TideRefresh(
        // Pull-to-refresh runs the same library update the header control
        // does — the gesture the Updates tab had, kept.
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            if (heroes.isNotEmpty)
              SliverToBoxAdapter(
                child: _Hero(
                  items: heroes,
                  index: _hero % heroes.length,
                  onOpen: _openSeries,
                  onRead: _resume,
                ),
              )
            else
              const SliverToBoxAdapter(child: _EmptyLibraryCard()),
            // Both sections always render, empty or not. Continue is the only
            // way to History now that Tide's glass bar has replaced the
            // Material one here, and a route that appears only when it happens
            // to have contents is a route the reader cannot rely on.
            SliverToBoxAdapter(
              child: TideSectionHeader(
                label: 'Continue',
                trailing: resuming.isEmpty ? null : '${resuming.length}',
                onTap: () => ref.read(homeTabIndexProvider.notifier).set(1),
              ),
            ),
            if (resuming.isEmpty)
              const SliverToBoxAdapter(
                child: _SectionEmpty('Nothing part-read right now.'),
              )
            else
              SliverToBoxAdapter(
                child: _ContinueRail(
                  entries: resuming,
                  onTap: _resume,
                  onLongPress: _openSeries,
                ),
              ),
            SliverToBoxAdapter(
              child: _TonightHeader(
                count: _visible.length,
                filtersActive: filters.isActive,
                searching: _searchingUpdates,
                onSearch: _openUpdatesSearch,
                onCloseSearch: _closeUpdatesSearch,
                onFilter: _openFilters,
                onUpcoming: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UpcomingScreen(),
                  ),
                ),
              ),
            ),
            if (_searchingUpdates)
              SliverToBoxAdapter(
                child: _UpdatesSearchField(
                  controller: _updatesSearch,
                  onChanged: (v) => setState(() => _updatesQuery = v.trim()),
                ),
              ),
            if (_rows.isEmpty)
              SliverToBoxAdapter(
                child: _SectionEmpty(
                  _updatesQuery.isNotEmpty
                      ? 'No updates match that.'
                      : filters.isActive
                          ? 'No updates match the current filter.'
                          : 'No new chapters waiting.',
                ),
              )
            else
              SliverList.builder(
                itemCount: _rows.length,
                itemBuilder: (context, i) => switch (_rows[i]) {
                  final _DayRow row => TideSectionHeader(
                      label: row.label,
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                    ),
                  final _UpdateRow row => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
                      child: _UpdateTile(
                        update: row.update,
                        selected: _selected.contains(row.update.chapterId),
                        selecting: _selecting,
                        onTap: () => _selecting
                            ? _toggleSelected(row.update.chapterId)
                            : _openChapter(
                                row.update.mangaId,
                                row.update.chapterId,
                              ),
                        onLongPress: () =>
                            _toggleSelected(row.update.chapterId),
                        onOpenSeries: () => _openSeries(row.update.mangaId),
                      ),
                    ),
                },
              ),
            // Clears the floating bar, and the selection bar when it's up.
            const SliverToBoxAdapter(child: SizedBox(height: 118)),
          ],
        ),
      ),
    );
  }

  /// Filters and day-groups the updates feed, memoised on everything that can
  /// change the result. Today's arrivals get no day header — the section is
  /// already called Tonight, and "TONIGHT / TODAY" says one thing twice.
  void _recomputeRows(List<LibraryUpdate> updates, UpdatesFilters filters) {
    final q = _updatesQuery.toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key = (
      updates,
      q,
      filters.unread,
      filters.bookmark,
      filters.hideMutedScanlators,
      today,
    );
    if (key == _rowsKey) return;

    _visible = updates.where((u) {
      if (q.isNotEmpty && !u.mangaTitle.toLowerCase().contains(q)) return false;
      if (!applyTriState(filters.unread, () => !u.read)) return false;
      if (!applyTriState(filters.bookmark, () => u.bookmark)) return false;
      if (filters.hideMutedScanlators && u.isScanlatorMuted) return false;
      return true;
    }).toList(growable: false);

    // The stream is already ordered date_fetch DESC, so a single pass groups
    // it — mirrors Kotlin `getUiModel()`'s insertSeparators over
    // `dateFetch.toLocalDate()`.
    final rows = <_FeedRow>[];
    String? lastLabel;
    for (final u in _visible) {
      final label = _dayLabel(u.dateFetch, today);
      if (label != lastLabel) {
        if (label != 'Today') rows.add(_DayRow(label));
        lastLabel = label;
      }
      rows.add(_UpdateRow(u));
    }
    _rows = rows;
    _rowsKey = key;
  }

  /// Greeting and the two round controls, or the selection header.
  Widget _header() {
    // The status-bar inset lives here rather than on the scroll view: the
    // feed scrolls under the status bar by design, but its FIRST row must
    // not start beneath the clock.
    final top = MediaQuery.paddingOf(context).top + 14;
    if (_selecting) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, 16),
        child: Row(
          children: [
            TideIconButton(
              icon: Icons.close_rounded,
              onTap: _clearSelection,
            ),
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
            TideIconButton(icon: Icons.select_all, onTap: _selectAll),
            const SizedBox(width: 9),
            TideIconButton(icon: Icons.flip_to_back, onTap: _invertSelection),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // No wordmark. The app does not need to introduce itself
                // every time it opens; the greeting is the whole header.
                Text(
                  tideGreeting(),
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.65,
                    color: TideColors.text,
                  ),
                ),
              ],
            ),
          ),
          TideIconButton(
            icon: Icons.search,
            onTap: () => ref.read(homeTabIndexProvider.notifier).set(2),
          ),
          const SizedBox(width: 9),
          // Where the avatar chip used to be. An avatar is a decoration; a
          // library that has not checked for new chapters is the one thing
          // this screen can actually be wrong about.
          _RefreshButton(updating: _updating, onTap: _refresh),
        ],
      ),
    );
  }
}

/// Round glass control that spins while a library update runs.
class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.updating, required this.onTap});

  final bool updating;
  final VoidCallback onTap;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.updating) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _RefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.updating && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.updating && _spin.isAnimating) {
      // Finish the turn it is on rather than snapping back to 0 — a control
      // that stops mid-rotation reads as a glitch.
      _spin.animateTo(1, duration: const Duration(milliseconds: 300)).then((_) {
        if (mounted && !widget.updating) _spin.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: TideGlass(
        radius: TideRadius.panel,
        tintTop: widget.updating ? 0.14 : 0.09,
        tintBottom: widget.updating ? 0.05 : 0.03,
        highlight: widget.updating ? 0.24 : 0.16,
        border: widget.updating ? 0.22 : 0.11,
        onTap: widget.updating ? null : widget.onTap,
        child: Center(
          child: RotationTransition(
            turns: _spin,
            child: Icon(
              Icons.refresh,
              size: 18,
              color: widget.updating
                  ? TideColors.accent
                  : TideColors.textAt(0.8),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tonight's own header: the section label, its count, and the three controls
/// the Updates toolbar carried — search, filter, and the route to Upcoming.
class _TonightHeader extends StatelessWidget {
  const _TonightHeader({
    required this.count,
    required this.filtersActive,
    required this.searching,
    required this.onSearch,
    required this.onCloseSearch,
    required this.onFilter,
    required this.onUpcoming,
  });

  final int count;
  final bool filtersActive;
  final bool searching;
  final VoidCallback onSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback onFilter;
  final VoidCallback onUpcoming;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'TONIGHT',
            style: TideText.kicker(size: 13, color: TideColors.textAt(0.5))
                .copyWith(letterSpacing: 1.82),
          ),
          const SizedBox(width: 10),
          if (count > 0)
            Text('$count', style: TideText.caption(size: 12, opacity: 0.35)),
          const Spacer(),
          _HeaderAction(
            icon: searching ? Icons.close_rounded : Icons.search,
            onTap: searching ? onCloseSearch : onSearch,
          ),
          _HeaderAction(
            icon: Icons.filter_list,
            lit: filtersActive,
            onTap: onFilter,
          ),
          _HeaderAction(icon: Icons.calendar_month_outlined, onTap: onUpcoming),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.onTap,
    this.lit = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 17,
          color: lit ? TideColors.accent : TideColors.textAt(0.45),
        ),
      ),
    );
  }
}

class _UpdatesSearchField extends StatelessWidget {
  const _UpdatesSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 40,
        child: TideGlass(
          radius: TideRadius.panel,
          tintTop: 0.09,
          tintBottom: 0.03,
          highlight: 0.16,
          border: 0.11,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: TideColors.textAt(0.42)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  cursorColor: TideColors.accent,
                  style: TideText.title(size: 14),
                  textInputAction: TextInputAction.search,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: 'Search updates',
                    hintStyle: TideText.title(
                      size: 14,
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
}

/// The rotating top-5 banner.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.items,
    required this.index,
    required this.onOpen,
    required this.onRead,
  });

  final List<LibraryItem> items;
  final int index;
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onRead;

  @override
  Widget build(BuildContext context) {
    final current = items[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(current.manga.id),
        child: Container(
          height: 404,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TideRadius.sheet),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 60,
                offset: const Offset(0, 26),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TideRadius.sheet),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cross-fade rather than slide: the banner is ambient, and a
                // slide would read as something the reader is expected to
                // keep up with.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1100),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(current.manga.id),
                    child: TideKenBurns(
                      child: TideCover(manga: current.manga, cacheWidth: 900),
                    ),
                  ),
                ),
                const Positioned.fill(child: TideScrim()),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 52,
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(index + 1).toString().padLeft(2, '0')} · MOST READ',
                          style: TideText.kicker(
                            color: TideColors.accent,
                          ).copyWith(letterSpacing: 2.2),
                        ),
                        const SizedBox(height: 8),
                        // Two lines, not three: at 34px a third line runs the
                        // title into the tag row and the Read button below it.
                        // Long titles ellipse rather than reflow the cluster.
                        Text(
                          current.manga.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.display(34),
                        ),
                        if (current.manga.genre?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final g in current.manga.genre!.take(3))
                                TideTag(g),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  bottom: 20,
                  child: _HeroDots(count: items.length, active: index),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _ReadButton(onTap: () => onRead(current.manga.id)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Five segments with a lit marker that slides between them.
class _HeroDots extends StatelessWidget {
  const _HeroDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    const width = 78.0;
    const gap = 7.0;
    final segment = (width - gap * (count - 1)) / count;
    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: 4,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  Container(
                    width: segment,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(TideRadius.tag),
                    ),
                  ),
                ],
              ],
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 700),
              curve: tideEase,
              left: active * (segment + gap),
              child: Container(
                width: segment,
                height: 4,
                decoration: BoxDecoration(
                  color: TideColors.accentLight,
                  borderRadius: BorderRadius.circular(TideRadius.tag),
                  boxShadow: [
                    BoxShadow(
                      color: TideColors.accent.withValues(alpha: 0.8),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TideGlass(
        radius: TideRadius.panel,
        // Sits on the hero's own scrim, which is already a flat wash — see
        // TideIconButton for why that means no BackdropFilter.
        blur: false,
        tintTop: 0.16,
        tintBottom: 0.06,
        highlight: 0.30,
        border: 0.20,
        saturation: 1.8,
        onTap: onTap,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        child: TideSheen(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 18, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow_rounded,
                    size: 18, color: TideColors.textBright),
                const SizedBox(width: 6),
                Text(
                  'Read',
                  style: TideText.title(size: 13.5)
                      .copyWith(color: TideColors.textBright),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One quiet line where a section has nothing to show.
class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Text(text, style: TideText.caption(size: 13, opacity: 0.35)),
    );
  }
}

/// Horizontal rail of part-read series.
class _ContinueRail extends StatelessWidget {
  const _ContinueRail({
    required this.entries,
    required this.onTap,
    required this.onLongPress,
  });

  final List<_Resuming> entries;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final e = entries[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(e.item.manga.id),
            onLongPress: () => onLongPress(e.item.manga.id),
            child: SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 182,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(TideRadius.pane),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(TideRadius.pane),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TideCover(manga: e.item.manga, cacheWidth: 320),
                          const Positioned.fill(child: TideScrim()),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 14,
                            child: Text(
                              e.item.manga.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TideText.display(19).copyWith(
                                color: TideColors.brightAt(0.9),
                              ),
                            ),
                          ),
                          // Position, drawn as a lit underline rather than a
                          // bar chart — the accent as a line, per Nocturne.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 4,
                              color: Colors.black.withValues(alpha: 0.5),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: e.ratio.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: TideColors.accent,
                                    boxShadow: [
                                      BoxShadow(
                                        color: TideColors.accent
                                            .withValues(alpha: 0.9),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '${e.chapterLabel} · ${(e.ratio * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(opacity: 0.55),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One arrival. Carries the state the Updates list carried: read rows go
/// quiet, bookmarks show, a muted scanlator strikes the title through, and a
/// selected row lights.
class _UpdateTile extends StatelessWidget {
  const _UpdateTile({
    required this.update,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenSeries,
  });

  final LibraryUpdate update;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOpenSeries;

  @override
  Widget build(BuildContext context) {
    final muted = update.isScanlatorMuted;
    final dim = update.read || muted;
    final subtitle = <String>[
      tideChapterLabel(update.chapterName, -1),
      if (update.scanlator != null && update.scanlator!.isNotEmpty)
        update.scanlator!,
      if (update.isLinkedAttribution) 'linked source',
      tideRelative(
        DateTime.fromMillisecondsSinceEpoch(
          update.dateFetch == 0 ? update.dateUpload : update.dateFetch,
        ),
      ),
    ].join(' · ');

    return TideGlass(
      radius: TideRadius.panel,
      tintTop: selected ? 0.16 : (dim ? 0.05 : 0.075),
      tintBottom: selected ? 0.05 : (dim ? 0.02 : 0.026),
      highlight: selected ? 0.20 : (dim ? 0.10 : 0.13),
      border: selected ? 0.30 : (dim ? 0.07 : 0.09),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: onLongPress,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // While selecting, the cover is part of the row rather than its
              // own target — otherwise half the tile silently opts out of the
              // selection you are building.
              onTap: selecting ? onTap : onOpenSeries,
              child: SizedBox(
                width: 44,
                height: 58,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TideRadius.chip),
                  child: Opacity(
                    opacity: dim ? 0.55 : 1,
                    child: _UpdateCover(update: update),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    update.mangaTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.title(
                      color: dim ? TideColors.textAt(0.5) : TideColors.text,
                    ).copyWith(
                      decoration:
                          muted ? TextDecoration.lineThrough : null,
                      decorationColor: TideColors.textAt(0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(opacity: dim ? 0.3 : 0.45),
                  ),
                ],
              ),
            ),
            if (update.bookmark) ...[
              const SizedBox(width: 10),
              const Icon(Icons.bookmark, size: 15, color: TideColors.accent),
            ],
            if (selecting) ...[
              const SizedBox(width: 10),
              _SelectMark(selected: selected),
            ] else if (!update.read && update.lastPageRead == 0) ...[
              const SizedBox(width: 10),
              const TideBadge('New'),
            ],
          ],
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
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color:
            selected ? TideColors.accent : Colors.white.withValues(alpha: 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? TideColors.accent
              : Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: TideColors.ground)
          : null,
    );
  }
}

/// Cover for an update row, resolved through the shared cover cache and the
/// source's own image headers.
///
/// This used to open a second full-library stream PER ROW to find the manga
/// that owned the cover; the update projection already carries the source id
/// and thumbnail, which is everything the pipeline needs.
class _UpdateCover extends ConsumerWidget {
  const _UpdateCover({required this.update});

  final LibraryUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: TideCover.fallbackGradient(update.mangaId),
      ),
    );
    final url = ref
        .watch(coverCacheProvider)
        .coverUrlFor(update.mangaId, update.thumbnailUrl);
    if (url == null || url.isEmpty) return fallback;
    final headers = ref
        .watch(installedSourceImageHeadersProvider)
        .valueOrNull?[update.source];
    return SourceImage(
      url: url,
      headers: headers,
      cacheWidth: 180,
      fit: BoxFit.cover,
      placeholder: (_) => fallback,
      errorWidget: (_, _) => fallback,
    );
  }
}

/// Bulk actions over the current selection. Mirrors Kotlin's
/// `MangaBottomActionMenu` for the Updates tab: each action shows only when it
/// applies to what is actually selected.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selected,
    required this.onBookmark,
    required this.onUnbookmark,
    required this.onMarkRead,
    required this.onMarkUnread,
  });

  final List<LibraryUpdate> selected;
  final VoidCallback onBookmark;
  final VoidCallback onUnbookmark;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;

  @override
  Widget build(BuildContext context) {
    final anyNotBookmarked = selected.any((u) => !u.bookmark);
    final allBookmarked =
        selected.isNotEmpty && selected.every((u) => u.bookmark);
    final anyUnread = selected.any((u) => !u.read);
    final anyReadOrStarted =
        selected.any((u) => u.read || u.lastPageRead > 0);

    return SizedBox(
      height: 58,
      child: TideGlass(
        radius: TideRadius.sheet,
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
            if (anyNotBookmarked)
              _BarAction(
                icon: Icons.bookmark_add_outlined,
                label: 'Bookmark',
                onTap: onBookmark,
              ),
            if (allBookmarked)
              _BarAction(
                icon: Icons.bookmark_remove_outlined,
                label: 'Unbookmark',
                onTap: onUnbookmark,
              ),
            if (anyUnread)
              _BarAction(
                icon: Icons.done_all,
                label: 'Read',
                onTap: onMarkRead,
              ),
            if (anyReadOrStarted)
              _BarAction(
                icon: Icons.remove_done,
                label: 'Unread',
                onTap: onMarkUnread,
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
              style: TideText.caption(size: 10, opacity: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-axis filter sheet: unread (tri), bookmark (tri), and a flip for
/// hiding muted-scanlator rows entirely. Each tri-state cycles
/// off → include → exclude on tap.
class _UpdatesFilterSheet extends ConsumerWidget {
  const _UpdatesFilterSheet();

  static TriState _next(TriState v) => switch (v) {
        TriState.disabled => TriState.enabledIs,
        TriState.enabledIs => TriState.enabledNot,
        TriState.enabledNot => TriState.disabled,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(updatesFiltersProvider);
    final notifier = ref.read(updatesFiltersProvider.notifier);
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Filter updates', style: TideText.display(21)),
          const SizedBox(height: 18),
          _TriRow(
            label: 'Unread',
            value: filters.unread,
            onTap: () => notifier.setUnread(_next(filters.unread)),
          ),
          const SizedBox(height: 8),
          _TriRow(
            label: 'Bookmarked',
            value: filters.bookmark,
            onTap: () => notifier.setBookmark(_next(filters.bookmark)),
          ),
          const SizedBox(height: 8),
          TideRow(
            icon: Icons.volume_off_outlined,
            title: 'Hide muted scanlators',
            subtitle: 'When off, muted rows still show, struck through',
            lit: filters.hideMutedScanlators,
            onTap: () =>
                notifier.setHideMutedScanlators(!filters.hideMutedScanlators),
            trailing: TideSwitch(
              value: filters.hideMutedScanlators,
              onChanged: notifier.setHideMutedScanlators,
            ),
          ),
          const SizedBox(height: 20),
          TideButton(
            label: 'Done',
            primary: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// One tri-state axis: off, include, or exclude — stated in words, because
/// three states behind one icon is a puzzle.
class _TriRow extends StatelessWidget {
  const _TriRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TriState value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, state) = switch (value) {
      TriState.disabled => (Icons.check_box_outline_blank, 'Off'),
      TriState.enabledIs => (Icons.check_box, 'Include'),
      TriState.enabledNot => (Icons.disabled_by_default_outlined, 'Exclude'),
    };
    return TideRow(
      icon: icon,
      title: label,
      subtitle: state,
      lit: value != TriState.disabled,
      onTap: onTap,
    );
  }
}

/// Relative day label for a `date_fetch` epoch-ms value. Mirrors Kotlin's
/// `relativeDateText`: Today / Yesterday / weekday (within a week) / absolute
/// date. Kept identical to the History screen's grouping.
String _dayLabel(int epochMs, DateTime today) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final that = DateTime(t.year, t.month, t.day);
  // Calendar days, not elapsed hours — see [calendarDaysBetween]. A future
  // `date_fetch` (a source that dates a chapter ahead) no longer takes the
  // weekday branch.
  final diffDays = calendarDaysBetween(that, today);
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Yesterday';
  if (diffDays > 1 && diffDays < 7) return _weekdayName(that.weekday);
  return '${that.year}-${that.month.toString().padLeft(2, '0')}-'
      '${that.day.toString().padLeft(2, '0')}';
}

String _weekdayName(int weekday) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[(weekday - 1) % 7];
}

class _EmptyLibraryCard extends StatelessWidget {
  const _EmptyLibraryCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: TideEmpty(
        title: 'Nothing here yet',
      ),
    );
  }
}

