// ===========================================================================
// Tide settings.
//
// A directory, nothing more — grouped by what each entry governs: what you
// read, how the app behaves, and what it does with your data.
//
// Laid out two-up rather than as one column of full-width rows. Ten identical
// rows, each an icon and a title and a comma-list of three nouns, is a wall:
// every line the same height, the same shape and the same weight, so nothing
// is findable except by reading all of it top to bottom. Halving the run and
// letting the icon carry the identification makes it scannable at a glance,
// which is all a directory has to be.
//
// The comma-lists went with it. They had drifted into being wrong — Advanced
// promised "dump crash logs, battery optimizations" and has neither — and a
// three-noun list is not read as information anyway. Each tile gets two or
// three words that say what is actually behind it.
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
      // The settings HUB builds its own scaffold rather than PrefScaffold
      // (it is a list of destinations, not of preferences), so it does not
      // inherit the aurora the way its eleven sub-screens do — it has to
      // carry its own, or it is the one flat screen in the branch.
      body: Stack(
        children: [
          const Positioned.fill(
            child: TideAurora(opacity: TideAuroraLevel.dense),
          ),
          TideRise(
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
                      hint: 'Updates, categories',
                      destination: LibrarySettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.chrome_reader_mode_outlined,
                      title: 'Reader',
                      hint: 'Modes, display',
                      destination: ReaderSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.explore_outlined,
                      title: 'Browse',
                      hint: 'Source list',
                      destination: BrowseSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.sync_outlined,
                      title: 'Tracking',
                      hint: 'Progress sync',
                      destination: TrackersSettingsScreen(),
                    ),
                  ]),
                  TideSectionHeader(label: 'App'),
                  _Group([
                    _Entry(
                      icon: Icons.palette_outlined,
                      title: 'Appearance',
                      hint: 'Theme, formats',
                      destination: AppearanceSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.security_outlined,
                      title: 'Security',
                      hint: 'Lock, secure screen',
                      destination: SecuritySettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.code_outlined,
                      title: 'Advanced',
                      hint: 'Logging, caches',
                      destination: AdvancedSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.info_outlined,
                      title: 'About',
                      hint: 'Version, links',
                      destination: AboutScreen(),
                    ),
                  ]),
                  TideSectionHeader(label: 'Data'),
                  _Group([
                    _Entry(
                      icon: Icons.get_app,
                      title: 'Downloads',
                      hint: 'Auto, removal',
                      destination: DownloadSettingsScreen(),
                    ),
                    _Entry(
                      icon: Icons.storage_outlined,
                      title: 'Data and storage',
                      hint: 'Backups, space',
                      destination: DataStorageSettingsScreen(),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }
}

/// Lays a group out two per row. Rows of `Expanded` pairs rather than a
/// GridView: every group here is short and already in a ListView, so a grid
/// would only add a scroll-inside-a-scroll and an aspect ratio to keep in
/// sync with the tallest tile.
class _Group extends StatelessWidget {
  const _Group(this.entries);

  final List<_Entry> entries;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      final left = entries[i];
      final right = i + 1 < entries.length ? entries[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 8),
              // An odd entry takes half the width and leaves the other half
              // empty, rather than stretching to full width and reading as a
              // different kind of thing than its neighbours.
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            row,
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
    required this.hint,
    required this.destination,
  });

  final IconData icon;
  final String title;

  /// Two or three words on what is actually behind the tile. Not a list of
  /// every control on the screen — see the note at the top of the file.
  final String hint;

  final Widget destination;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: TideRadius.panel,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(TideRadius.chip),
              border: Border.all(color: TideColors.hairline),
            ),
            child: Icon(icon, size: 18, color: TideColors.textAt(0.75)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TideText.title(size: 15),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TideText.caption(size: 12, opacity: 0.38),
          ),
        ],
      ),
    );
  }
}
