import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/updater/app_update_checker.dart';

/// About / version info. Mirrors the Kotlin `AboutScreen` layout: logo
/// header, the Mohyeong description + AI-collaboration note, the version /
/// check-for-updates / what's-new / open-source-licenses rows, and the
/// Website / Help / GitHub link row at the bottom.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static const _websiteUrl = 'https://sjoygsh.github.io/Mohyeong/';
  static const _helpUrl = 'https://sjoygsh.github.io/Mohyeong/help.html';
  static const _githubUrl = 'https://github.com/sjoygsh/Mohyeong';
  static const _releaseUrl =
      'https://github.com/sjoygsh/Mohyeong/releases/latest';

  // Verbatim from the Kotlin AboutScreen description block.
  static const _description =
      'Mohyeong (모형) is an enhanced open-source manga reader for Android. '
      'It is a fork of Mihon — itself a continuation of Tachiyomi — with '
      'additional features for power users: linked sources, multi-backend '
      'cloud sync (SyncYomi · WebDAV · Google Drive · Dropbox), and per-row '
      'timestamp-based conflict resolution.';
  static const _aiNote =
      'Developed with the assistance of Claude AI (Anthropic). AI '
      'collaboration was an intentional and integral part of the development '
      'process — not hidden.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final info = snap.data!;
          final version = '${info.version} (${info.buildNumber})';
          return ListView(
            children: [
              // LogoHeader equivalent (matches the More tab logo header).
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: Center(
                  child: Icon(
                    Icons.menu_book,
                    size: 64,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _aiNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Version'),
                subtitle: Text(version),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: 'Mohyeong $version'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              ListTile(
                title: const Text('Check for updates'),
                onTap: () => _checkForUpdates(context, ref),
              ),
              ListTile(
                title: const Text("What's new"),
                onTap: () => _open(_releaseUrl),
              ),
              ListTile(
                title: const Text('Open source licenses'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Mohyeong',
                  applicationVersion: version,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _LinkIcon(
                      label: 'Website',
                      icon: Icons.language,
                      url: _websiteUrl,
                    ),
                    _LinkIcon(
                      label: 'Help',
                      icon: Icons.help_outline,
                      url: _helpUrl,
                    ),
                    _LinkIcon(
                      label: 'GitHub',
                      icon: Icons.code,
                      url: _githubUrl,
                    ),
                  ],
                ),
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

/// A labelled, tappable icon mirroring Kotlin's `LinkIcon` — an icon button
/// over a small caption that opens [url] in the browser.
class _LinkIcon extends StatelessWidget {
  const _LinkIcon({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final IconData icon;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(icon),
            tooltip: label,
            onPressed: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
