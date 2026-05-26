import 'package:flutter/material.dart';

/// "More" hub -- equivalent to the Kotlin MoreTab. Routes to Settings,
/// Categories, Data & Storage, About, etc. None of those destinations exist
/// yet, so each list item is a no-op for now.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <_MoreEntry>[
      _MoreEntry(icon: Icons.download_outlined, label: 'Downloads'),
      _MoreEntry(icon: Icons.category_outlined, label: 'Categories'),
      _MoreEntry(icon: Icons.cloud_sync_outlined, label: 'Sync'),
      _MoreEntry(icon: Icons.backup_outlined, label: 'Backup & restore'),
      _MoreEntry(icon: Icons.settings_outlined, label: 'Settings'),
      _MoreEntry(icon: Icons.info_outline, label: 'About'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          return ListTile(
            leading: Icon(entry.icon),
            title: Text(entry.label),
            trailing: const Icon(Icons.chevron_right),
            // TODO: route to each subscreen as it's implemented.
            onTap: () {},
          );
        },
      ),
    );
  }
}

class _MoreEntry {
  const _MoreEntry({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
