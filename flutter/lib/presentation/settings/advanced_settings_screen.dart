import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/network/app_http_client.dart';
import 'pref_tiles.dart';

/// Advanced sub-screen: data-maintenance actions. Mirror of the
/// blind-executable parts of Mihon's `SettingsAdvancedScreen` — clear
/// network cookies, clear the cover image cache, and clear non-library
/// database entries. Mihon's battery/network/DoH/crash-dump groups need
/// platform plumbing not yet built and are omitted.
class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        children: [
          const PrefSectionHeader('Network'),
          ListTile(
            leading: const Icon(Icons.cookie_outlined),
            title: const Text('Clear cookies'),
            subtitle: const Text(
              'Remove all stored cookies, including Cloudflare clearances.',
            ),
            onTap: () => _clearCookies(context, ref),
          ),
          const PrefSectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.image_not_supported_outlined),
            title: const Text('Clear cached covers'),
            subtitle: const Text(
              'Delete downloaded cover thumbnails (re-fetched on demand).',
            ),
            onTap: () => _clearCoverCache(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear database'),
            subtitle: const Text(
              'Remove manga that are not in your library, freeing space.',
            ),
            onTap: () => _clearDatabase(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCookies(BuildContext context, WidgetRef ref) async {
    await ref.read(appHttpClientProvider).cookies.deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cookies cleared.')),
      );
    }
  }

  Future<void> _clearCoverCache(BuildContext context) async {
    await DefaultCacheManager().emptyCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover cache cleared.')),
      );
    }
  }

  Future<void> _clearDatabase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear database'),
        content: const Text(
          'This permanently removes every manga that is not in your '
          'library, along with its chapters and history. Library entries '
          'are kept. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
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
