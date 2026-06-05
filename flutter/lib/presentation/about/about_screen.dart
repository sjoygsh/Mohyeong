import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/updater/app_update_checker.dart';

/// About / version info. Mirrors the Kotlin AboutScreen layout: app
/// name, version, and a few external links.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _repoUrl = 'https://github.com/sjoygsh/Mohyeong';
  static const _licenseUrl =
      'https://github.com/sjoygsh/Mohyeong/blob/main/LICENSE';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final info = snap.data!;
          return ListView(
            children: [
              const SizedBox(height: 24),
              Center(
                child: Icon(
                  Icons.menu_book,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  info.appName.isEmpty ? 'Mohyeong' : info.appName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'v${info.version} (${info.buildNumber})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('Check for updates'),
                onTap: () => _checkForUpdates(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Source code'),
                subtitle: const Text(_repoUrl),
                onTap: () => _open(_repoUrl),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('License'),
                onTap: () => _open(_licenseUrl),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Runs a forced update check and reports the outcome via a SnackBar.
  /// `forceCheck: true` bypasses Mihon's 3-day throttle since the user
  /// explicitly asked. On a newer release, offers a button that opens the
  /// GitHub release page in the browser.
  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates...')),
    );

    AppUpdateResult result;
    try {
      result =
          await ref.read(appUpdateCheckerProvider).checkForUpdate(forceCheck: true);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Update check failed')),
        );
      return;
    }

    messenger.hideCurrentSnackBar();
    switch (result) {
      case NewUpdate(:final release):
        messenger.showSnackBar(
          SnackBar(
            content: Text('New version available: ${release.version}'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _open(release.releaseLink),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      case NoNewUpdate():
        messenger.showSnackBar(
          const SnackBar(content: Text('No new updates available')),
        );
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
