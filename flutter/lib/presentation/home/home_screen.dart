import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/app_route_observer.dart';
import '../../data/base/base_preferences.dart';
import '../../data/download/download_repository.dart';
import '../../data/source/extension_updates.dart';
import '../../data/source/incognito_preferences.dart';
import '../library/library_screen.dart';
import '../tide/tide.dart';
import '../tide/tide_home_screen.dart';
import '../history/history_screen.dart';
import '../browse/browse_screen.dart';
import '../more/more_screen.dart';

/// Selected top-level home tab. Held in a provider (rather than local widget
/// state) so launcher app-shortcuts can jump straight to a tab on launch —
/// mirrors the Kotlin `MainActivity.handleIntentAction` setting the active tab.
class HomeTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final homeTabIndexProvider = NotifierProvider<HomeTabIndex, int>(
  HomeTabIndex.new,
);

/// Fired when the user taps the bottom-nav destination for the tab they're
/// already on. Mirrors Kotlin `Tab.onReselect`: each tab decides what to do
/// (Library opens its settings sheet; the list tabs scroll back to top). The
/// monotonically increasing [tick] lets listeners distinguish repeated
/// reselects of the same tab. [tab] is `-1` before any reselect.
typedef HomeReselectSignal = ({int tab, int tick});

class HomeReselect extends Notifier<HomeReselectSignal> {
  @override
  HomeReselectSignal build() => (tab: -1, tick: 0);

  void signal(int tab) => state = (tab: tab, tick: state.tick + 1);
}

final homeReselectProvider =
    NotifierProvider<HomeReselect, HomeReselectSignal>(HomeReselect.new);

/// Set while a tab is showing its own floating bar — a multi-select, which
/// puts bulk actions exactly where the navigation sits. Two glass bars stacked
/// on one screen edge is worse than either alone.
final tideBarSuppressedProvider = StateProvider<bool>((_) => false);

/// Four top-level destinations: Home, History, Browse, More. Updates is gone
/// — new chapters surface on the home feed's Tonight section, so a whole tab
/// that answered the same question was one place too many to look.
///
/// Each tab is kept alive across switches via [IndexedStack] so list scroll
/// positions and ongoing requests survive a tap on a different tab -- same
/// behaviour the Voyager-based Kotlin nav provides.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  /// The four tab bodies, in bar order.
  ///
  /// These used to be `_HomeTab` records carrying a label, an icon and a
  /// selectedIcon as well. Nothing had read any of those three since the
  /// Material `NavigationBar` was deleted — `TideTabBar` owns the glyphs
  /// (they are the app's own shapes, not generic destination icons, so they
  /// belong with the bar). Only the child was ever used, so that is all this
  /// is now.
  ///
  /// Tab 0 is Tide: a reading queue rather than a shelf. The full library
  /// grid is still one tap away, from Tide's own glass bar.
  static const _tabs = <Widget>[
    TideHomeScreen(),
    HistoryScreen(),
    BrowseScreen(),
    MoreScreen(),
  ];

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  /// Whether the bottom navigation bar is currently shown. It hides while the
  /// active tab is scrolled toward its content and reappears when scrolling
  /// back toward the top — a 1:1 port of Kotlin HomeScreen's
  /// `hideOnScrollConnection` driving an `AnimatedVisibility` with
  /// `expandVertically()` / `shrinkVertically()`.
  bool _bottomNavVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The scheduled background update runs in its own engine isolate with
    // its own DownloadRepository, so chapters it auto-downloaded while the
    // app was backgrounded never pass through this isolate's index
    // mutators. Re-walk on the next read after coming back to the front.
    if (state == AppLifecycleState.resumed) {
      ref.read(downloadRepositoryProvider).invalidateDownloadedIndex();
    }
  }

  /// Mirrors the Kotlin `onPreScroll` thresholds (±1px): scrolling toward the
  /// end of the list hides the nav, scrolling back toward the top reveals it.
  ///
  /// Kotlin's `onPreScroll` sees the OFFERED drag delta even when the list is
  /// pinned at an edge; Flutter reports that case as [OverscrollNotification]
  /// instead of a [ScrollUpdateNotification]. Both must be handled — otherwise
  /// a bar hidden while the list sits at the top (or on a tab too short to
  /// scroll) can never be revealed, and the bar is the only way off the tab.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final double delta;
    if (notification is ScrollUpdateNotification) {
      delta = notification.scrollDelta ?? 0;
    } else if (notification is OverscrollNotification) {
      delta = notification.overscroll;
    } else {
      return false;
    }
    if (delta > 1 && _bottomNavVisible) {
      setState(() => _bottomNavVisible = false);
    } else if (delta < -1 && !_bottomNavVisible) {
      setState(() => _bottomNavVisible = true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final incognito = ref.watch(incognitoModeProvider);
    final downloadedOnly = ref.watch(downloadedOnlyProvider);
    final index = ref.watch(homeTabIndexProvider);
    // Browse badge: extensions with an available update (Kotlin
    // extensionUpdatesCount). Not gated by a pref — Kotlin has none.
    final extensionsBadge = ref.watch(extUpdatesCountProvider);
    final barSuppressed = ref.watch(tideBarSuppressedProvider);
    ref.listen<int>(homeTabIndexProvider, (_, _) {
      // Re-show the nav on any tab switch. The only way to change tabs while
      // the bar is hidden is the back-to-Library PopScope below, and the new
      // tab may have nothing to scroll (Compose can't get stuck here — drags
      // always reach Kotlin's onPreScroll even on unscrollable content — so
      // this is the Flutter-side escape hatch, not a behaviour difference).
      if (!_bottomNavVisible) {
        setState(() => _bottomNavVisible = true);
      }
    });
    // Mirrors Kotlin HomeScreen's BackHandler: when not on the Library tab,
    // the back button returns to it rather than leaving the app.
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(homeTabIndexProvider.notifier).set(0);
      },
      child: Scaffold(
        backgroundColor: TideColors.ground,
        body: Stack(children: [
        Positioned.fill(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kotlin AppStateBanners: downloaded-only sits above incognito;
            // only the topmost banner absorbs the status-bar inset.
            if (downloadedOnly) const _DownloadedOnlyBanner(),
            if (incognito)
              downloadedOnly
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: const _IncognitoBanner(),
                    )
                  : const _IncognitoBanner(),
            Expanded(
              // The raw pointer listener is the reveal-only escape hatch: a
              // tab whose content fits the viewport has no scrollable to
              // notify (Compose can't get trapped like this — every drag
              // reaches Kotlin's onPreScroll), so a hidden bar could become
              // permanent — the bar is the only way off the tab. Hiding stays
              // scroll-notification-driven, matching Kotlin.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerMove: (event) {
                  if (!_bottomNavVisible && event.delta.dy > 1) {
                    setState(() => _bottomNavVisible = true);
                  }
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: _FadeThroughIndexedStack(
                    index: index,
                    children: HomeScreen._tabs,
                  ),
                ),
              ),
            ),
          ],
        )),
        // ONE navigation, floating over every tab. It used to be Tide's glass
        // bar on tab 0 and a Material NavigationBar on the other three, which
        // is the single loudest way an app can look like two apps.
        //
        // Slides clear of the content rather than fading in place: the bar is
        // an object, so it should leave the way an object would.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: tideEase,
          left: 40,
          right: 40,
          bottom: _bottomNavVisible && !barSuppressed ? 26 : -80,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _bottomNavVisible && !barSuppressed ? 1 : 0,
            child: _badgedBar(
              TideTabBar(
                activeTab: index,
                onSelect: (i) {
                  // Tapping the already-selected destination is a "reselect" —
                  // forward it to the tab instead of re-setting the same index.
                  if (i == index) {
                    ref.read(homeReselectProvider.notifier).signal(i);
                  } else {
                    ref.read(homeTabIndexProvider.notifier).set(i);
                  }
                },
                onLibrary: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LibraryScreen(),
                  ),
                ),
              ),
              extensionsBadge,
            ),
          ),
        ),
      ]),
      ),
    );
  }

  /// Extension-updates count, marked on the bar's Browse slot. The bar draws
  /// its own icons, so the badge rides as an overlay dot rather than wrapping
  /// a destination the way Kotlin's BadgedBox does.
  Widget _badgedBar(Widget bar, int extBadge) {
    if (extBadge <= 0) return bar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bar,
        Positioned(
          // Browse is the fourth of five evenly-spaced slots.
          left: 0,
          right: 0,
          top: 12,
          child: FractionallySizedBox(
            widthFactor: 1,
            child: Align(
              alignment: const Alignment(0.52, 0),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TideColors.accent,
                  boxShadow: [
                    BoxShadow(
                      color: TideColors.accent.withValues(alpha: 0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A mode the whole app is running in, said once across the top.
///
/// Kotlin's `AppStateBanners` fills the strip with `tertiary` / `primary` and
/// writes on it in the matching `on-` colour. Held to Tide's rule — the accent
/// draws lines and glows, never floods — that would be the largest wash of
/// colour anywhere in the app, sitting permanently above every screen. So it
/// is a lit hairline under a quiet label instead: the same "this is on"
/// reading the lit [TideRow]s in More already use for these two modes.
class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.label, required this.onTap});

  final String label;

  /// Tapping turns the mode off — an invisible convenience over Kotlin's
  /// non-interactive banner.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TideColors.accent.withValues(alpha: 0.10),
          border: Border(
            bottom: BorderSide(
              color: TideColors.accent.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TideText.kicker(color: TideColors.accentLight),
            ),
          ),
        ),
      ),
    );
  }
}

/// Persistent strip shown while "Downloaded only" mode is active. Mirrors
/// Kotlin `DownloadedOnlyModeBanner`.
class _DownloadedOnlyBanner extends ConsumerWidget {
  const _DownloadedOnlyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModeBanner(
      label: 'Downloaded only',
      onTap: () => ref.read(downloadedOnlyProvider.notifier).set(false),
    );
  }
}

/// Persistent strip shown while global incognito mode is active. Mirrors the
/// Kotlin `IncognitoModeBanner` (Banners.kt), whose label is
/// `MR.strings.pref_incognito_mode`.
class _IncognitoBanner extends ConsumerWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ModeBanner(
      label: 'Incognito mode',
      onTap: () => ref.read(incognitoModeProvider.notifier).set(false),
    );
  }
}

/// [IndexedStack] whose index changes play Mihon's tab-switch motion: the
/// Kotlin HomeScreen wraps the current tab in `AnimatedContent` with
/// `materialFadeThroughIn(initialScale = 1f) togetherWith
/// materialFadeThroughOut` over `TabFadeDuration` (200ms) — a scale-free
/// fade-through: the old tab fades out over the first 35% (accelerate
/// easing), the new one fades in over the remaining 65% (decelerate easing).
///
/// Because the two fades never overlap, one opacity over the stack with the
/// index swapped at the 35% crossover reproduces it exactly, while the
/// [IndexedStack] keeps every tab alive (scroll positions, in-flight loads)
/// just like the raw stack did.
///
/// Tabs build lazily: an [IndexedStack] normally builds ALL children up
/// front, which ran five screens' inits and DB stream queries on cold start.
/// A tab is swapped in on its first visit and stays alive after — the same
/// lifecycle as Mihon's Voyager tabs, which are created on first show and
/// then retained.
class _FadeThroughIndexedStack extends StatefulWidget {
  const _FadeThroughIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<_FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  // Compose's FastOutLinearInEasing / LinearOutSlowInEasing, the pair
  // materialFadeThroughOut/In use.
  static const _accelerate = Cubic(0.4, 0.0, 1.0, 1.0);
  static const _decelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200), // Kotlin TabFadeDuration
  );

  late final Animation<double> _opacity = _controller.drive(
    TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: _accelerate)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: _decelerate)),
        weight: 65,
      ),
    ]),
  );

  /// The tab the stack is currently showing; trails [widget.index] until the
  /// fade-out completes.
  late int _shown = widget.index;

  /// Tabs that have been visited and therefore actually build; the rest stay
  /// [SizedBox.shrink] placeholders until first shown.
  late final Set<int> _built = {widget.index};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_swapAtCrossover);
    // Pre-warm the unvisited tabs during post-launch idle, one per pass, so
    // the first switch to each lands on an already-built screen (its DB
    // streams primed) instead of paying the whole first build inside the
    // 200ms fade. Lazy-build keeps the cold-start critical path short; this
    // moves the deferred cost into idle time shortly after instead of into
    // the user's first tap.
    // This does overlap the launch wordmark, and that was measured rather than
    // assumed: three release cold starts with the warm-up held back until the
    // intro finished, three without, zero skipped frames in all six. Holding
    // it only delayed the warm-up. (A debug build stalls ~1s twice here, but
    // that is JIT compiling the tree, not this.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 600), _warmNextTab);
    });
  }

  void _warmNextTab() {
    if (!mounted) return;
    var next = -1;
    for (var i = 0; i < widget.children.length; i++) {
      if (!_built.contains(i)) {
        next = i;
        break;
      }
    }
    if (next == -1) return;
    setState(() => _built.add(next));
    // Space the warms out a frame + a beat apart so five screen inits never
    // stack into one long frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), _warmNextTab);
    });
  }

  void _swapAtCrossover() {
    if (_controller.value >= 0.35 && _shown != widget.index) {
      setState(() => _shown = widget.index);
    }
  }

  @override
  void didUpdateWidget(covariant _FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      // Build the incoming tab now, during the fade-out, so its first (and
      // possibly heavy) build isn't crammed into the fade-in half. It isn't
      // painted until [_shown] swaps at the crossover.
      _built.add(widget.index);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(
        index: _shown,
        children: [
          // Every built tab is wrapped, always — a wrapper that comes and
          // goes would move its child in the tree and remount the screen.
          // [_shown] rather than widget.index so the outgoing tab counts as
          // visible until the crossover, which is when it stops being drawn.
          for (final (i, child) in widget.children.indexed)
            if (_built.contains(i))
              TabVisibility(visible: i == _shown, child: child)
            else
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}

