// ===========================================================================
// Tide about.
//
// The one screen where the app is allowed to say what it is, so the version is
// the headline rather than a row two thirds down, and the description reads as
// prose instead of as a settings entry.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/updater/app_update_checker.dart';
import '../tide/tide.dart';
import '../util/open_link.dart';

/// About / version info. Mirrors the Kotlin `AboutScreen` content: the
/// Mohyeong description + AI-collaboration note, the version /
/// check-for-updates / what's-new / open-source-licenses rows, and the
/// Website / Help / GitHub links.
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
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          Positioned.fill(
            child: TideRise(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TideHeader(title: 'About'),
                  Expanded(
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: TideSpinner(),
                          );
                        }
                        final info = snap.data!;
                        final version =
                            '${info.version} (${info.buildNumber})';
                        return _body(context, ref, version);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, String version) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // The version, as the headline — it is the fact people open this
        // screen for, and it used to be the subtitle of the fifth row down.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mohyeong', style: TideText.display(38)),
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: 'Mohyeong $version'),
                  );
                  TideToast.of(context).show('Copied to clipboard');
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      version,
                      style: TideText.title(size: 15)
                          .copyWith(color: TideColors.accent),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.content_copy_outlined,
                      size: 14,
                      color: TideColors.textAt(0.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_description, style: TideText.body()),
              const SizedBox(height: 14),
              Text(
                _aiNote,
                style: TideText.caption(size: 12.5, opacity: 0.45)
                    .copyWith(height: 1.55),
              ),
            ],
          ),
        ),
        const TideSectionHeader(label: 'Version'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TideRow(
                icon: Icons.system_update_alt,
                title: 'Check for updates',
                trailing: const TideChevron(),
                onTap: () => _checkForUpdates(context, ref),
              ),
              const SizedBox(height: 8),
              TideRow(
                icon: Icons.new_releases_outlined,
                title: "What's new",
                trailing: Icon(
                  Icons.open_in_new,
                  size: 15,
                  color: TideColors.textAt(0.3),
                ),
                onTap: () => _open(_releaseUrl),
              ),
              const SizedBox(height: 8),
              TideRow(
                icon: Icons.balance_outlined,
                title: 'Open source licenses',
                trailing: const TideChevron(),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Mohyeong',
                  applicationVersion: version,
                ),
              ),
            ],
          ),
        ),
        const TideSectionHeader(label: 'Links'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _LinkTile(
                label: 'Website',
                icon: Icons.language_outlined,
                url: _websiteUrl,
              ),
              SizedBox(width: 8),
              _LinkTile(
                label: 'Help',
                icon: Icons.help_outlined,
                url: _helpUrl,
              ),
              SizedBox(width: 8),
              _LinkTile(
                label: 'GitHub',
                icon: Icons.code_outlined,
                url: _githubUrl,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Runs a forced update check and reports the outcome.
  /// `forceCheck: true` bypasses Mihon's 3-day throttle since the user
  /// explicitly asked. On a newer release, offers a button that opens the
  /// GitHub release page in the browser.
  ///
  /// The old SnackBar version had to hide the in-progress message before
  /// showing the result, or the two would queue and the outcome would appear
  /// seconds after the check finished. A toast replaces whatever is on screen,
  /// so the result simply takes the place of "Checking…".
  Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
    final toast = TideToast.of(context);
    toast.show('Checking for updates...');

    AppUpdateResult result;
    try {
      result = await ref
          .read(appUpdateCheckerProvider)
          .checkForUpdate(forceCheck: true);
    } catch (_) {
      toast.show('Update check failed');
      return;
    }

    switch (result) {
      case NewUpdate(:final release):
        toast.show(
          'New version available: ${release.version}',
          actionLabel: 'View',
          onAction: () => _open(release.releaseLink),
          // Kept from the SnackBar it replaces: long enough to read a version
          // number and decide, which the default action dwell is not.
          duration: const Duration(seconds: 8),
        );
      case NoNewUpdate():
        toast.show('No new updates available');
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// A labelled destination off the app — Kotlin's `LinkIcon`, given enough
/// room to be tappable and enough label to be readable.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final IconData icon;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TideGlass(
        radius: TideRadius.pane,
        padding: const EdgeInsets.symmetric(vertical: 16),
        onTap: () => openLink(context, url),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: TideColors.textAt(0.7)),
            const SizedBox(height: 8),
            Text(label, style: TideText.caption(size: 11.5, opacity: 0.6)),
          ],
        ),
      ),
    );
  }
}
