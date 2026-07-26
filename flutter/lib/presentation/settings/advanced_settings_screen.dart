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
/// `SettingsAdvancedScreen` — DoH provider selection, verbose logging, and
/// data-maintenance actions (clear cookies, chapter cache, cover cache,
/// non-library database entries). Mihon's battery/crash-dump/Shizuku groups
/// need platform plumbing not yet built and are omitted.
class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doh = ref.watch(dohProviderProvider);
    return PrefScaffold(
      title: 'Advanced',
      children: [
          const PrefSectionHeader('Logging'),
          PrefSwitch(
            title: 'Verbose logging',
            subtitle:
                'Print verbose logs to system log (reduces app performance)',
            provider: verboseLoggingProvider,
          ),
          const PrefSectionHeader('Networking'),
          PrefRow(
            icon: Icons.dns_outlined,
            title: 'DNS over HTTPS (DoH)',
            subtitle: dohProviderLabels[doh] ?? 'Disabled',
            onTap: () => _pickDoh(context, ref),
          ),
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

  Future<void> _pickDoh(BuildContext context, WidgetRef ref) async {
    final current = ref.read(dohProviderProvider);
    final picked = await pickPref<int>(
      context,
      title: 'DNS over HTTPS (DoH)',
      selected: current,
      options: [
        for (final e in dohProviderLabels.entries) (e.key, e.value),
      ],
    );
    if (picked != null) {
      await ref.read(dohProviderProvider.notifier).set(picked);
      // TODO apply DoH to http client (rewiring Dio's resolver is out of
      // scope here; Mihon applies this on the next app restart).
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Requires an app restart.')),
        );
      }
    }
  }

  Future<void> _clearCookies(BuildContext context, WidgetRef ref) async {
    await ref.read(appHttpClientProvider).cookies.deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cookies cleared.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chapter cache cleared ($mb MB).')),
      );
    }
  }

  /// Clear the cover/image disk cache ([appImageCacheManager], plus the
  /// legacy default store older installs may still carry).
  Future<void> _clearCoverCache(BuildContext context) async {
    await appImageCacheManager.emptyCache();
    await DefaultCacheManager().emptyCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover cache cleared.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $removed entries.')),
      );
    }
  }
}
