import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/browse_preferences.dart';
import 'pref_tiles.dart';

/// Browse sub-screen: source-list and NSFW preferences. Mirror of Mihon's
/// `SettingsBrowseScreen`. The Cloudflare auto-solve toggle and extension-
/// repo manager from Mihon are omitted here — Cloudflare solving is a
/// manual webview flow (no auto path to gate) and the extension-repo store
/// has no management UI yet.
class BrowseSettingsScreen extends ConsumerWidget {
  const BrowseSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: ListView(
        children: [
          const PrefSectionHeader('Sources'),
          PrefSwitch(
            title: 'Hide in-library items',
            subtitle: 'Hide manga already in your library from source '
                'browse and search results.',
            provider: hideInLibraryItemsProvider,
          ),
          const PrefSectionHeader('NSFW content'),
          PrefSwitch(
            title: 'Show NSFW sources',
            subtitle: 'Display sources flagged 18+ (not yet active).',
            provider: showNsfwSourceProvider,
          ),
        ],
      ),
    );
  }
}
