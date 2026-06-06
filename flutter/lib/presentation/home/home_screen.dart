import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final homeTabIndexProvider =
    NotifierProvider<HomeTabIndex, int>(HomeTabIndex.new);

/// The five top-level destinations match the Kotlin app's [HomeScreen.Tab]:
/// Library, Updates, History, Browse, More.
///
/// Each tab is kept alive across switches via [IndexedStack] so list scroll
/// positions and ongoing requests survive a tap on a different tab -- same
/// behaviour the Voyager-based Kotlin nav provides.
class HomeScreen extends ConsumerWidget {
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
      icon: Icons.update_outlined,
      selectedIcon: Icons.update,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final incognito = ref.watch(incognitoModeProvider);
    final index = ref.watch(homeTabIndexProvider);
    return Scaffold(
      body: Column(
        children: [
          if (incognito) const _IncognitoBanner(),
          Expanded(
            child: IndexedStack(
              index: index,
              children: _tabs.map((t) => t.child).toList(growable: false),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(homeTabIndexProvider.notifier).set(i),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

/// Persistent strip shown while global incognito mode is active. Tapping it
/// turns incognito off — mirroring Mihon's incognito banner / its
/// "Disable incognito mode" affordance.
class _IncognitoBanner extends ConsumerWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: () => ref.read(incognitoModeProvider.notifier).set(false),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.no_encryption_gmailerrorred_outlined,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Incognito mode',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Text(
                  'Turn off',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
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
