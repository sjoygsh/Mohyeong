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
    return PrefScaffold(
      title: 'Browse',
      children: [
          const PrefSectionHeader('Sources'),
          PrefSwitch(
            title: 'Hide entries already in library',
            provider: hideInLibraryItemsProvider,
          ),
          const PrefSectionHeader('NSFW (18+) sources'),
          PrefSwitch(
            title: 'Show in sources and extensions lists',
            subtitle: 'Not yet active.',
            provider: showNsfwSourceProvider,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'This does not prevent unofficial or potentially incorrectly '
              'flagged extensions from surfacing NSFW (18+) content within '
              'the app.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
    );
  }
}
