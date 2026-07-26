// ===========================================================================
// Tide settings.
//
// A directory, nothing more — so it is ten rows and no invention. Grouped by
// what they actually govern rather than run as one undifferentiated column:
// what you read, how the app behaves, and what it does with your data.
// ===========================================================================

import 'package:flutter/material.dart';

import '../about/about_screen.dart';
import '../tide/tide.dart';
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
/// a categorical list where each row pushes the matching sub-screen.
/// Sub-screens own the actual preference UI.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TideHeader(title: 'Settings'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: const [
                  TideSectionHeader(
                    label: 'Reading',
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                  ),
                  _Group([
                    _Entry(
                      icon: Icons.collections_bookmark_outlined,
                      title: 'Library',
                      subtitle: 'Categories, global update, chapter swipe',
                      destination: LibrarySettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.chrome_reader_mode_outlined,
                      title: 'Reader',
                      subtitle: 'Reading mode, display, navigation',
                      destination: ReaderSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.explore_outlined,
                      title: 'Browse',
                      subtitle: 'Sources, extensions, global search',
                      destination: BrowseSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.sync_outlined,
                      title: 'Tracking',
                      subtitle: 'One-way progress sync, enhanced sync',
                      destination: TrackersSettingsScreen(),
                    ),
                  ]),
                  TideSectionHeader(label: 'App'),
                  _Group([
                    _Entry(
                      icon: Icons.palette_outlined,
                      title: 'Appearance',
                      subtitle: 'Theme, date & time format',
                      destination: AppearanceSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.security_outlined,
                      title: 'Security and privacy',
                      subtitle: 'App lock, secure screen',
                      destination: SecuritySettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.code_outlined,
                      title: 'Advanced',
                      subtitle: 'Dump crash logs, battery optimizations',
                      destination: AdvancedSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.info_outline,
                      title: 'About',
                      subtitle: 'Version and links',
                      destination: AboutScreen(),
                    ),
                  ]),
                  TideSectionHeader(label: 'Data'),
                  _Group([
                    _Entry(
                      icon: Icons.get_app,
                      title: 'Downloads',
                      subtitle: 'Automatic download, download ahead',
                      destination: DownloadSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.storage_outlined,
                      title: 'Data and storage',
                      subtitle: 'Manual & automatic backups, storage space',
                      destination: DataStorageSettingsScreen(),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.entries);

  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, entry) in entries.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            entry,
          ],
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
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
    return TideRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const TideChevron(),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      ),
    );
  }
}
