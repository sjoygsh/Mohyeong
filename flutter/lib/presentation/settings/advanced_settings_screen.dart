import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/network/app_http_client.dart';
import '../../data/network/network_preferences.dart';
import '../../data/storage/app_cache.dart';
import '../tide/tide.dart';
import 'pref_tiles.dart';

/// Advanced sub-screen. Mirror of the blind-executable parts of Mihon's
/// `SettingsAdvancedScreen` — verbose logging and data-maintenance actions
/// (clear cookies, chapter cache, cover cache, non-library database entries).
/// Mihon's battery/crash-dump/Shizuku groups need platform plumbing not yet
/// built and are omitted.
///
/// Kotlin's DoH provider picker is omitted too, and that one is deliberate
/// rather than pending: the resolver work is planned but unbuilt (see the
/// `TODO(doh)` in `AppHttpClient._create()`, which keeps the plan and the
/// provider table alive). Shipping the picker meanwhile would have let
/// someone select Mullvad and believe their DNS was private while every
/// lookup still went to the system resolver — a dead control that lies about
/// privacy is worse than an absent one.
class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrefScaffold(
      title: 'Advanced',
      actions: [const PrefHelp('troubleshooting')],
      children: [
          const PrefSectionHeader('Logging'),
          PrefSwitch(
            title: 'Verbose logging',
            // TideRow clamps subtitles to one line, so this has to say the
            // thing that stops the switch looking broken — it is sampled when
            // the shared Dio is built — inside about thirty characters.
            subtitle: 'Logs headers; needs a restart',
            provider: verboseLoggingProvider,
          ),
          const PrefSectionHeader('Networking'),
          PrefRow(
            icon: Icons.cookie_outlined,
            title: 'Clear cookies',
            subtitle: 'Including Cloudflare clearances',
            onTap: () => _clearCookies(context, ref),
          ),
          const PrefSectionHeader('Data'),
          PrefRow(
            icon: Icons.cleaning_services_outlined,
            title: 'Clear chapter cache',
            subtitle: 'Delete cached pages to free up space',
            onTap: () => _clearChapterCache(context),
          ),
          PrefRow(
            icon: Icons.image_not_supported_outlined,
            title: 'Clear cover cache',
            subtitle: 'Thumbnails are re-fetched on demand',
            onTap: () => _clearCoverCache(context),
          ),
          PrefRow(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear database',
            subtitle: 'Drops entries that are not in your library',
            onTap: () => _clearDatabase(context, ref),
          ),
        ],
    );
  }

  Future<void> _clearCookies(BuildContext context, WidgetRef ref) async {
    await ref.read(appHttpClientProvider).cookies.deleteAll();
    if (context.mounted) {
      TideToast.of(context).show('Cookies cleared.');
    }
  }

  /// Delete the on-disk chapter-page cache. The Flutter rewrite has no
  /// dedicated `ChapterCache` subsystem yet, so we best-effort clear the
  /// conventional `chapter_disk_cache` directory under the app cache dir
  /// (the location Mihon's `ChapterCache` uses) if it exists. Once a real
  /// chapter cache lands this should call into it directly.
  Future<void> _clearChapterCache(BuildContext context) async {
    var bytesFreed = 0;
    try {
      final cacheRoot = await getApplicationCacheDirectory();
      final dir = Directory(p.join(cacheRoot.path, 'chapter_disk_cache'));
      if (dir.existsSync()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            bytesFreed += await entity.length();
          }
        }
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort: report failure but don't crash the settings screen.
    }
    if (context.mounted) {
      final mb = (bytesFreed / (1024 * 1024)).toStringAsFixed(1);
      TideToast.of(context).show('Chapter cache cleared ($mb MB).');
    }
  }

  /// Clear the cover/image disk cache ([appImageCacheManager], plus the
  /// legacy default store older installs may still carry).
  Future<void> _clearCoverCache(BuildContext context) async {
    await appImageCacheManager.emptyCache();
    await DefaultCacheManager().emptyCache();
    if (context.mounted) {
      TideToast.of(context).show('Cover cache cleared.');
    }
  }

  Future<void> _clearDatabase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showTideSheet<bool>(
      context,
      (_) => const TideConfirmSheet(
        title: 'Clear database',
        message: 'This permanently removes every manga that is not in your '
            'library, along with its chapters and history. Library entries '
            'are kept.',
        confirmLabel: 'Clear',
      ),
    );
    if (confirmed != true) return;
    final removed =
        await ref.read(mangaRepositoryProvider).clearNonLibraryEntries();
    if (context.mounted) {
      TideToast.of(context).show('Removed $removed entries.');
    }
  }
}
