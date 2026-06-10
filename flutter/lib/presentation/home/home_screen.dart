import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/base/base_preferences.dart';
import '../../data/source/incognito_preferences.dart';
import '../library/library_screen.dart';
import '../updates/updates_screen.dart';
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

/// The five top-level destinations match the Kotlin app's [HomeScreen.Tab]:
/// Library, Updates, History, Browse, More.
///
/// Each tab is kept alive across switches via [IndexedStack] so list scroll
/// positions and ongoing requests survive a tap on a different tab -- same
/// behaviour the Voyager-based Kotlin nav provides.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const _tabs = <_HomeTab>[
    _HomeTab(
      label: 'Library',
      icon: Icons.collections_bookmark_outlined,
      selectedIcon: Icons.collections_bookmark,
      child: LibraryScreen(),
    ),
    _HomeTab(
      label: 'Updates',
      icon: Icons.new_releases_outlined,
      selectedIcon: Icons.new_releases,
      child: UpdatesScreen(),
    ),
    _HomeTab(
      label: 'History',
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      child: HistoryScreen(),
    ),
    _HomeTab(
      label: 'Browse',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore,
      child: BrowseScreen(),
    ),
    _HomeTab(
      label: 'More',
      icon: Icons.more_horiz_outlined,
      selectedIcon: Icons.more_horiz,
      child: MoreScreen(),
    ),
  ];

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Whether the bottom navigation bar is currently shown. It hides while the
  /// active tab is scrolled toward its content and reappears when scrolling
  /// back toward the top — a 1:1 port of Kotlin HomeScreen's
  /// `hideOnScrollConnection` driving an `AnimatedVisibility` with
  /// `expandVertically()` / `shrinkVertically()`.
  bool _bottomNavVisible = true;

  /// Mirrors the Kotlin `onPreScroll` thresholds (±1px): scrolling toward the
  /// end of the list hides the nav, scrolling back toward the top reveals it.
  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    final delta = notification.scrollDelta ?? 0;
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
    // Mirrors Kotlin HomeScreen's BackHandler: when not on the Library tab,
    // the back button returns to it rather than leaving the app.
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(homeTabIndexProvider.notifier).set(0);
      },
      child: Scaffold(
        body: Column(
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
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: IndexedStack(
                  index: index,
                  children: HomeScreen._tabs
                      .map((t) => t.child)
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
        // shrinkTowards = Bottom: collapse the bar toward the screen edge while
        // freeing its layout space (so content expands up), matching Kotlin's
        // shrinkVertically(). The bar widget itself is built once and clipped.
        bottomNavigationBar: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 1, end: _bottomNavVisible ? 1 : 0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, factor, child) => ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: factor,
              child: child,
            ),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) {
              // Tapping the already-selected destination is a "reselect" —
              // forward it to the tab instead of re-setting the same index.
              if (i == index) {
                ref.read(homeReselectProvider.notifier).signal(i);
              } else {
                ref.read(homeTabIndexProvider.notifier).set(i);
              }
            },
            destinations: [
              for (final tab in HomeScreen._tabs)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.selectedIcon),
                  label: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent strip shown while global incognito mode is active. Mirrors the
/// Kotlin `IncognitoModeBanner` (Banners.kt): a thin, full-width strip in the
/// `primary` colour with centred `onPrimary` text reading "Incognito mode"
/// (`MR.strings.pref_incognito_mode`), `labelMedium`, 4dp padding.
///
/// Tapping it turns incognito off — an invisible convenience over Kotlin's
/// non-interactive banner; the appearance is unchanged.
/// Persistent strip shown while "Downloaded only" mode is active. Mirrors
/// Kotlin `DownloadedOnlyModeBanner`: `tertiary` strip with centred
/// `onTertiary` "Downloaded only" text. Tapping turns the mode off (same
/// convenience as the incognito banner below).
class _DownloadedOnlyBanner extends ConsumerWidget {
  const _DownloadedOnlyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiary,
      child: InkWell(
        onTap: () => ref.read(downloadedOnlyProvider.notifier).set(false),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'Downloaded only',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncognitoBanner extends ConsumerWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      child: InkWell(
        onTap: () => ref.read(incognitoModeProvider.notifier).set(false),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'Incognito mode',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTab {
  const _HomeTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
}
