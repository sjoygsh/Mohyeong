import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/browse_preferences.dart';
import 'pref_tiles.dart';

/// Browse sub-screen: source-list preferences. Mirror of Mihon's
/// `SettingsBrowseScreen`, minus three of its controls. Cloudflare solving is
/// a manual webview flow here, so there is no auto path to gate; the
/// extension-repo store has no management UI yet; and Mihon's NSFW-sources
/// toggle reads `tachiyomi.extension.nsfw` off each extension APK's manifest
/// metadata, which the JS extension contract has no equivalent for. With no
/// flag to filter on, that switch could only ever have written to storage.
class BrowseSettingsScreen extends ConsumerWidget {
  const BrowseSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrefScaffold(
      title: 'Browse',
      actions: [const PrefHelp('sources')],
      children: [
        const PrefSectionHeader('Sources'),
        PrefSwitch(
          title: 'Hide entries already in library',
          provider: hideInLibraryItemsProvider,
        ),
      ],
    );
  }
}
