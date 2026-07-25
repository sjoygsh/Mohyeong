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
//   tonight   chapters that landed since you last read
//
// Every section is fed by a repository stream the app already maintains, so
// this is a new presentation of existing state, not a new source of truth.
// ===========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/history/history_repository.dart';
import '../../data/library/library_repository.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/library/model/library_item.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../reader/reader_screen.dart';
import 'tide.dart';
import 'tide_series_screen.dart';

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

class TideHomeScreen extends ConsumerStatefulWidget {
  const TideHomeScreen({super.key});

  @override
  ConsumerState<TideHomeScreen> createState() => _TideHomeScreenState();
}

class _TideHomeScreenState extends ConsumerState<TideHomeScreen> {
  // Held rather than rebuilt per frame: a stream recreated inside build()
  // re-subscribes on every rebuild and the list flickers back to its loading
  // state. Same pattern the Updates and History screens use.
  late final Stream<List<LibraryItem>> _library =
      ref.read(libraryRepositoryProvider).watchAll();
  late final Stream<List<HistoryWithContext>> _history =
      ref.read(historyRepositoryProvider).watchRecent();
  late final Stream<List<LibraryUpdate>> _updates =
      ref.read(updatesRepositoryProvider).watchAll();

  final _scroll = ScrollController();

  /// Index of the hero currently shown; advanced on a timer.
  int _hero = 0;
  Timer? _rotate;

  /// Whether the floating bar is showing. It gets out of the way while you
  /// read down the feed and comes back the moment you scroll up — the same
  /// rule the Material nav follows, kept because a bar that permanently
  /// covers the last row of content is worse than no bar.
  bool _barVisible = true;

  bool _onScroll(ScrollNotification n) {
    // Horizontal rails (the Continue carousel) must not move the bar.
    if (n.metrics.axis != Axis.vertical) return false;
    final double delta;
    if (n is ScrollUpdateNotification) {
      delta = n.scrollDelta ?? 0;
    } else if (n is OverscrollNotification) {
      delta = n.overscroll;
    } else {
      return false;
    }
    if (delta > 1 && _barVisible) {
      setState(() => _barVisible = false);
    } else if (delta < -1 && !_barVisible) {
      setState(() => _barVisible = true);
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  /// Top 5 by completion ratio, counting only entries actually started — the
  /// same "what are you working through" rule the library carousel uses.
  List<LibraryItem> _topRead(List<LibraryItem> items) {
    final started = items
        .where((it) => it.totalCount > 0 && it.readCount > 0)
        .toList(growable: false);
    started.sort((a, b) =>
        (b.readCount / b.totalCount).compareTo(a.readCount / a.totalCount));
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

  Future<void> _openSeries(int mangaId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TideSeriesScreen(mangaId: mangaId),
        ),
      );

  Future<void> _openChapter(int mangaId, int chapterId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReaderScreen(mangaId: mangaId, chapterId: chapterId),
        ),
      );

  /// Open the oldest unread chapter — reading order, not release order. Same
  /// resolution the library grid's resume affordance performs.
  Future<void> _resume(int mangaId) async {
    final messenger = ScaffoldMessenger.of(context);
    final chapters =
        await ref.read(chapterRepositoryProvider).getByMangaId(mangaId);
    final unread = chapters.where((c) => !c.read).toList()
      ..sort((a, b) => b.sourceOrder.compareTo(a.sourceOrder));
    if (!mounted) return;
    if (unread.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No unread chapters left.')),
      );
      return;
    }
    await _openChapter(mangaId, unread.first.id);
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
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora()),
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
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
          ),
          // Slides clear of the content rather than fading in place: the bar
          // is an object, so it should leave the way an object would.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: tideEase,
            left: 40,
            right: 40,
            bottom: _barVisible ? 26 : -80,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _barVisible ? 1 : 0,
              child: const _TideTabBar(),
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
        child: CircularProgressIndicator(color: TideColors.accent),
      );
    }
    final heroes = _topRead(items);
    final resuming = _resuming(items, history);
    // Tonight is what arrived and has not been read yet — the list is a queue,
    // so a chapter leaves it once it has been.
    final tonight =
        updates.where((u) => !u.read).take(12).toList(growable: false);

    return TideRise(
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 60, bottom: 118),
        children: [
          const _Header(),
          if (heroes.isNotEmpty)
            _Hero(
              items: heroes,
              index: _hero % heroes.length,
              onOpen: (id) => _openSeries(id),
              onRead: (id) => _resume(id),
            )
          else
            const _EmptyLibraryCard(),
          // Both sections always render, empty or not. They are the only way
          // to History and Updates now that Tide's glass bar has replaced the
          // Material one here, and a route that appears only when it happens
          // to have contents is a route the reader cannot rely on.
          _SectionHeader(
            label: 'Continue',
            trailing: resuming.isEmpty ? null : '${resuming.length}',
            onTap: () => ref.read(homeTabIndexProvider.notifier).set(2),
          ),
          if (resuming.isEmpty)
            const _SectionEmpty('Nothing part-read right now.')
          else
            _ContinueRail(
              entries: resuming,
              onTap: (mangaId) => _resume(mangaId),
              onLongPress: (mangaId) => _openSeries(mangaId),
            ),
          _SectionHeader(
            label: 'Tonight',
            trailing: tonight.isEmpty ? null : '${tonight.length}',
            onTap: () => ref.read(homeTabIndexProvider.notifier).set(1),
          ),
          if (tonight.isEmpty)
            const _SectionEmpty('No new chapters waiting.')
          else
            _TonightList(
              updates: tonight,
              onTap: (u) => _openChapter(u.mangaId, u.chapterId),
              onOpenSeries: (u) => _openSeries(u.mangaId),
            ),
        ],
      ),
    );
  }
}

/// Greeting, wordmark and the two round controls.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tideGreeting().toUpperCase(), style: TideText.kicker()),
                const SizedBox(height: 1),
                Text(
                  'Tide',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.44,
                    color: TideColors.text,
                  ),
                ),
              ],
            ),
          ),
          TideIconButton(
            icon: Icons.search,
            onTap: () => ref.read(homeTabIndexProvider.notifier).set(3),
          ),
          const SizedBox(width: 9),
          // The design's avatar chip. It leads to More, which is where every
          // account-shaped thing in the app already lives.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(homeTabIndexProvider.notifier).set(4),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8D81D6), Color(0xFF3F5F86)],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
        ],
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
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 60,
                offset: const Offset(0, 26),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
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
                      borderRadius: BorderRadius.circular(9),
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
                  borderRadius: BorderRadius.circular(9),
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
        radius: 21,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label.toUpperCase(),
              style: TideText.kicker(size: 13, color: TideColors.textAt(0.5))
                  .copyWith(letterSpacing: 1.82),
            ),
            const Spacer(),
            if (trailing != null)
              Text(trailing!, style: TideText.caption(size: 12, opacity: 0.35)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 16, color: TideColors.textAt(0.35)),
            ],
          ],
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
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
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

/// Chapters that have arrived and not been read.
class _TonightList extends StatelessWidget {
  const _TonightList({
    required this.updates,
    required this.onTap,
    required this.onOpenSeries,
  });

  final List<LibraryUpdate> updates;
  final ValueChanged<LibraryUpdate> onTap;
  final ValueChanged<LibraryUpdate> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, u) in updates.indexed) ...[
            if (i > 0) const SizedBox(height: 9),
            TideGlass(
              radius: 18,
              onTap: () => onTap(u),
              padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onOpenSeries(u),
                    child: SizedBox(
                      width: 44,
                      height: 58,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: TideCover.fallbackGradient(u.mangaId),
                          ),
                          child: _UpdateThumb(update: u),
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
                          u.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.title(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tideChapterLabel(u.chapterName, -1)} · '
                          '${tideRelative(
                            DateTime.fromMillisecondsSinceEpoch(
                              u.dateFetch == 0 ? u.dateUpload : u.dateFetch,
                            ),
                          )}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TideText.caption(),
                        ),
                      ],
                    ),
                  ),
                  // Only the freshest arrival is marked; a badge on every row
                  // marks nothing.
                  if (i == 0) ...[
                    const SizedBox(width: 10),
                    const TideBadge('New'),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cover thumbnail for an update row, resolved through the shared cover
/// pipeline via the manga's own record.
class _UpdateThumb extends ConsumerWidget {
  const _UpdateThumb({required this.update});

  final LibraryUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<LibraryItem>>(
      stream: ref.read(libraryRepositoryProvider).watchAll(),
      builder: (context, snap) {
        final item = snap.data
            ?.where((it) => it.manga.id == update.mangaId)
            .firstOrNull;
        if (item == null) return const SizedBox.shrink();
        return TideCover(manga: item.manga, cacheWidth: 180);
      },
    );
  }
}

class _EmptyLibraryCard extends StatelessWidget {
  const _EmptyLibraryCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TideGlass(
        radius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
        child: Column(
          children: [
            Text('Nothing in the tide yet', style: TideText.display(24)),
            const SizedBox(height: 10),
            Text(
              'Add a series to your library and it will surface here — what '
              'you are part-way through, and what arrived overnight.',
              textAlign: TextAlign.center,
              style: TideText.body(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating glass bar.
///
/// Icon SHAPES are the app's existing ones, not the design's generic
/// home/book/search/person set — these destinations do specific things, and a
/// magnifier standing in for Browse or a person for More reads wrong the
/// moment you tap it. The glass is the design; the glyphs are the app's.
class _TideTabBar extends ConsumerWidget {
  const _TideTabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 58,
      child: TideGlass(
        radius: 29,
        // The one BackdropFilter left on this screen: the bar genuinely
        // floats over scrolling covers, so there is something behind it worth
        // blurring.
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
            const _TabIcon(icon: Icons.home, active: true),
            _TabIcon(
              icon: Icons.collections_bookmark_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _LibraryGridRoute(),
                ),
              ),
            ),
            _TabIcon(
              icon: Icons.history_outlined,
              onTap: () => ref.read(homeTabIndexProvider.notifier).set(2),
            ),
            _TabIcon(
              icon: Icons.explore_outlined,
              onTap: () => ref.read(homeTabIndexProvider.notifier).set(3),
            ),
            _TabIcon(
              icon: Icons.more_horiz,
              onTap: () => ref.read(homeTabIndexProvider.notifier).set(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, this.active = false, this.onTap});

  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 52,
        height: 58,
        child: Icon(
          icon,
          size: 22,
          color: active ? TideColors.accentLight : TideColors.textAt(0.5),
        ),
      ),
    );
  }
}

/// The existing library grid, reachable from the Tide bar. Tide's home is a
/// reading queue; this is still where you go to browse the whole shelf.
class _LibraryGridRoute extends StatelessWidget {
  const _LibraryGridRoute();

  @override
  Widget build(BuildContext context) => const LibraryScreen();
}
