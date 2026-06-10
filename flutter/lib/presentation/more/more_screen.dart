import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/base/base_preferences.dart';
import '../../data/source/incognito_preferences.dart';
import '../about/about_screen.dart';
import '../categories/categories_screen.dart';
import '../downloads/download_queue_screen.dart';
import '../home/home_screen.dart';
import '../settings/data_storage_settings_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';

/// "More" hub -- equivalent to the Kotlin MoreScreen. Routes to Settings,
/// Categories, Data and storage, About, etc. Also hosts the global
/// incognito toggle and the app logo header, mirroring Mihon's MoreScreen.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  /// Verbatim Kotlin `Constants.URL_HELP`.
  static const _urlHelp = 'https://sjoygsh.github.io/Mohyeong/help.html';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incognito = ref.watch(incognitoModeProvider);
    // Mirrors Kotlin MoreTab.onReselect: tapping the already-selected More
    // bottom-nav destination (index 4) opens the Settings screen.
    ref.listen<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab == 4 && next.tick != (prev?.tick ?? 0)) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
      }
    });

    // Kotlin MoreScreen has no app bar; the list starts with a centred logo.
    return Scaffold(
      body: ListView(
        children: [
          const _LogoHeader(),
          // Verbatim Mihon strings label_downloaded_only / _summary.
          SwitchListTile(
            secondary: const Icon(Icons.cloud_off_outlined),
            title: const Text('Downloaded only'),
            subtitle: const Text('Filters all entries in your library'),
            value: ref.watch(downloadedOnlyProvider),
            onChanged: ref.read(downloadedOnlyProvider.notifier).set,
          ),
          // Verbatim Mihon strings pref_incognito_mode / _summary.
          SwitchListTile(
            secondary: const Icon(Icons.no_encryption_gmailerrorred_outlined),
            title: const Text('Incognito mode'),
            subtitle: const Text('Pauses reading history'),
            value: incognito,
            onChanged: ref.read(incognitoModeProvider.notifier).set,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.get_app),
            title: const Text('Download queue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadQueueScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.label_outlined),
            title: const Text('Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CategoriesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.query_stats),
            title: const Text('Statistics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Data and storage'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DataStorageSettingsScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => launchUrl(
              Uri.parse(_urlHelp),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors Kotlin `LogoHeader`: a centred, `onSurface`-tinted app logo
/// (64dp) padded 32dp vertically, with a divider beneath it.
class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Icon(
            Icons.menu_book,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
