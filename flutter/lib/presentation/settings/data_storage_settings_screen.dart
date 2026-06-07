import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/source/local_source_preferences.dart';
import '../../data/source/saf.dart';
import '../backup/backup_screen.dart';
import '../sync/sync_settings_screen.dart';

/// Data & storage sub-screen: storage location + backup/restore + sync.
/// Mirrors the "Data and storage" section of Mihon's settings.
class DataStorageSettingsScreen extends StatelessWidget {
  const DataStorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data and storage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Guide',
            onPressed: () => launchUrl(
              Uri.parse('https://sjoygsh.github.io/Mohyeong/help.html#storage'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _StorageLocationTile(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Used for automatic backups, chapter downloads, and local '
              'source.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(height: 1),
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

/// The storage-location row, equivalent to Mihon's `storageLocationPicker` /
/// `storageLocationText` in SettingsDataScreen. Tapping launches the system
/// folder picker (SAF) and persists the chosen tree URI to
/// `__APP_STATE_storage_dir`.
class _StorageLocationTile extends ConsumerStatefulWidget {
  const _StorageLocationTile();

  @override
  ConsumerState<_StorageLocationTile> createState() =>
      _StorageLocationTileState();
}

class _StorageLocationTileState extends ConsumerState<_StorageLocationTile> {
  String? _displayName;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _refreshName();
  }

  Future<void> _refreshName() async {
    final uri = ref.read(storageDirProvider);
    if (uri == null) {
      if (mounted) setState(() => _displayName = null);
      return;
    }
    final name = Saf.isContentUri(uri) ? await Saf.displayName(uri) : uri;
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final uri = await Saf.openTree();
      if (uri != null) {
        await ref.read(storageDirProvider.notifier).set(uri);
        await _refreshName();
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = ref.watch(storageDirProvider);
    return ListTile(
      leading: _picking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.folder_outlined),
      title: const Text('Storage location'),
      subtitle: Text(
        uri == null ? 'No storage location set' : (_displayName ?? uri),
      ),
      onTap: _picking ? null : _pick,
    );
  }
}
