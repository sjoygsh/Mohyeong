import 'package:flutter/material.dart';

import '../about/about_screen.dart';
import '../backup/backup_screen.dart';
import '../categories/categories_screen.dart';
import '../downloads/download_queue_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../sync/sync_settings_screen.dart';

/// "More" hub -- equivalent to the Kotlin MoreTab. Routes to Settings,
/// Categories, Data & Storage, About, etc. Destinations that don't have
/// a screen yet are left as no-op tiles.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <_MoreEntry>[
      _MoreEntry(
        icon: Icons.download_outlined,
        label: 'Download queue',
        builder: (_) => const DownloadQueueScreen(),
      ),
      _MoreEntry(
        icon: Icons.category_outlined,
        label: 'Categories',
        builder: (_) => const CategoriesScreen(),
      ),
      _MoreEntry(
        icon: Icons.bar_chart_outlined,
        label: 'Statistics',
        builder: (_) => const StatsScreen(),
      ),
      _MoreEntry(
        icon: Icons.cloud_sync_outlined,
        label: 'Sync',
        builder: (_) => const SyncSettingsScreen(),
      ),
      _MoreEntry(
        icon: Icons.backup_outlined,
        label: 'Backup & restore',
        builder: (_) => const BackupScreen(),
      ),
      _MoreEntry(
        icon: Icons.settings_outlined,
        label: 'Settings',
        builder: (_) => const SettingsScreen(),
      ),
      _MoreEntry(
        icon: Icons.info_outline,
        label: 'About',
        builder: (_) => const AboutScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          final builder = entry.builder;
          return ListTile(
            leading: Icon(entry.icon),
            title: Text(entry.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: builder == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: builder),
                    ),
          );
        },
      ),
    );
  }
}

class _MoreEntry {
  const _MoreEntry({
    required this.icon,
    required this.label,
    this.builder,
  });
  final IconData icon;
  final String label;
  final WidgetBuilder? builder;
}
