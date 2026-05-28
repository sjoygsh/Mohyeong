import 'package:flutter/material.dart';

import '../backup/backup_screen.dart';
import '../sync/sync_settings_screen.dart';

/// Data & storage sub-screen: backup/restore + sync configuration.
class DataStorageSettingsScreen extends StatelessWidget {
  const DataStorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data and storage')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Backup & restore'),
            subtitle: const Text('Mihon-compatible .tachibk export/import'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BackupScreen(),
              ),
            ),
          ),
          ListTile(
            title: const Text('Sync'),
            subtitle:
                const Text('SyncYomi, WebDAV, Google Drive, or Dropbox'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SyncSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
