import 'package:flutter/material.dart';

import '../about/about_screen.dart';
import '../track/trackers_settings_screen.dart';
import 'advanced_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'browse_settings_screen.dart';
import 'data_storage_settings_screen.dart';
import 'download_settings_screen.dart';
import 'library_settings_screen.dart';
import 'reader_settings_screen.dart';
import 'security_settings_screen.dart';

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
            subtitle: 'Theme, date & time format',
            destination: const AppearanceSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.collections_bookmark_outlined,
            title: 'Library',
            subtitle: 'Categories, global update, chapter swipe',
            destination: const LibrarySettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.chrome_reader_mode_outlined,
            title: 'Reader',
            subtitle: 'Reading mode, display, navigation',
            destination: const ReaderSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.get_app,
            title: 'Downloads',
            subtitle: 'Automatic download, download ahead',
            destination: const DownloadSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.sync_outlined,
            title: 'Tracking',
            subtitle: 'One-way progress sync, enhanced sync',
            destination: const TrackersSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.explore_outlined,
            title: 'Browse',
            subtitle: 'Sources, extensions, global search',
            destination: const BrowseSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.storage_outlined,
            title: 'Data and storage',
            subtitle: 'Manual & automatic backups, storage space',
            destination: const DataStorageSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.security_outlined,
            title: 'Security and privacy',
            subtitle: 'App lock, secure screen',
            destination: const SecuritySettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.code_outlined,
            title: 'Advanced',
            subtitle: 'Dump crash logs, battery optimizations',
            destination: const AdvancedSettingsScreen(),
          ),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'Version and links',
            destination: const AboutScreen(),
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
