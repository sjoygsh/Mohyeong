import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_screen.dart';
import '../updates/updates_screen.dart';
import '../history/history_screen.dart';
import '../browse/browse_screen.dart';
import '../more/more_screen.dart';

/// The five top-level destinations match the Kotlin app's [HomeScreen.Tab]:
/// Library, Updates, History, Browse, More.
///
/// Each tab is kept alive across switches via [IndexedStack] so list scroll
/// positions and ongoing requests survive a tap on a different tab -- same
/// behaviour the Voyager-based Kotlin nav provides.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

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
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs.map((t) => t.child).toList(growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
