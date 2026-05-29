import 'package:flutter/material.dart';

import '../track/trackers_settings_screen.dart';
import 'advanced_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'browse_settings_screen.dart';
import 'data_storage_settings_screen.dart';
import 'download_settings_screen.dart';
import 'library_settings_screen.dart';
import 'reader_settings_screen.dart';

/// Top-level Settings screen. Mirror of Mihon's `SettingsMainScreen`:
/// a categorical list where each tile pushes the matching sub-screen.
/// Sub-screens own the actual preference UI.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme and colours',
            destination: const AppearanceSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.collections_bookmark_outlined,
            title: 'Library',
            subtitle: 'Update interval',
            destination: const LibrarySettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.menu_book_outlined,
            title: 'Reader',
            subtitle: 'Default reading mode',
            destination: const ReaderSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.download_outlined,
            title: 'Downloads',
            subtitle: 'Simultaneous downloads, auto-download',
            destination: const DownloadSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.explore_outlined,
            title: 'Browse',
            subtitle: 'Sources and NSFW content',
            destination: const BrowseSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.sync_outlined,
            title: 'Tracking',
            subtitle: 'AniList, MyAnimeList, and more',
            destination: const TrackersSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.storage_outlined,
            title: 'Data and storage',
            subtitle: 'Backup, restore, and sync',
            destination: const DataStorageSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.code_outlined,
            title: 'Advanced',
            subtitle: 'Clear cookies, cache, and database',
            destination: const AdvancedSettingsScreen(),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget destination;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      ),
    );
  }
}
