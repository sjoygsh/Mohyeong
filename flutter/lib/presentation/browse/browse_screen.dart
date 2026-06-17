import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/extension_updates.dart';
import '../../data/source/incognito_preferences.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/local_source.dart';
import '../../data/source/local_source_preferences.dart';
import '../../data/source/source_preferences.dart';
import '../home/home_screen.dart';
import 'global_search_screen.dart';
import 'migrate_source_screen.dart';
import 'source_browse_screen.dart';
import 'source_preferences_screen.dart';
import 'sources_filter_screen.dart';

/// Browse hosts three sub-tabs: Sources (installed sources you can browse),
/// Extensions (install / uninstall management), and Migrate (moves
/// favourites from one source to another).
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirrors Kotlin BrowseTab.onReselect: tapping the already-selected Browse
    // bottom-nav destination (index 3) opens the global search screen.
    ref.listen<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab == 3 && next.tick != (prev?.tick ?? 0)) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const GlobalSearchScreen(),
          ),
        );
      }
    });
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Browse'),
          actions: [
            // Kotlin MigrateSourceTab's HelpOutline action — only while the
            // Migrate tab is active (per-tab toolbar actions, like Kotlin's
            // TabContent.actions).
            Builder(
              builder: (innerContext) {
                final tabs = DefaultTabController.of(innerContext);
                return AnimatedBuilder(
                  animation: tabs,
                  builder: (_, _) => tabs.index == 2
                      ? IconButton(
                          icon: const Icon(Icons.help_outline),
                          tooltip: 'Migration help',
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'https://sjoygsh.github.io/Mohyeong/help.html'
                              '#source-migration',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
            Builder(
              builder: (innerContext) => IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Global search',
                onPressed: () {
                  Navigator.of(innerContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GlobalSearchScreen(),
                    ),
                  );
                },
              ),
            ),
            Builder(
              builder: (innerContext) => IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter sources',
                onPressed: () {
                  Navigator.of(innerContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SourcesFilterScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sources'),
              Tab(text: 'Extensions'),
              Tab(text: 'Migrate'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SourcesTab(),
            _ExtensionsTab(),
            MigrateSourceTab(),
          ],
        ),
      ),
    );
  }
}

class _SourcesTab extends ConsumerWidget {
  const _SourcesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(extensionRepositoryProvider);
    final prefsAsync = ref.watch(localSourcePreferencesProvider);
    final sourcePrefsAsync = ref.watch(sourcePreferencesProvider);
    return StreamBuilder<List<InstalledExtension>>(
      stream: repo.watchInstalled(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allExtensions = snap.data!;
        final sourcePrefs = sourcePrefsAsync.value;
        final localRoot = prefsAsync.value?.root;
        // Listen to the language + hidden-source sets so toggles on the
        // filter screen reflect immediately when the user pops back.
        // While prefs are still loading, fall through to "show all".
        return StreamBuilder<Set<String>>(
          stream: sourcePrefs?.watchEnabledLanguages(),
          initialData: sourcePrefs?.getEnabledLanguages(),
          builder: (context, langSnap) {
            return StreamBuilder<Set<String>>(
              stream: sourcePrefs?.watchDisabledSources(),
              initialData: sourcePrefs?.getDisabledSources(),
              builder: (context, disSnap) {
                return StreamBuilder<Set<String>>(
                  stream: sourcePrefs?.watchPinnedSources(),
                  initialData: sourcePrefs?.getPinnedSources(),
                  builder: (context, pinSnap) {
                    final enabledLangs = langSnap.data ?? const <String>{};
                    final disabledIds = disSnap.data ?? const <String>{};
                    final pinnedIds = pinSnap.data ?? const <String>{};
                    final extensions = sourcePrefs == null
                        ? allExtensions
                        : allExtensions
                            .where((e) =>
                                // Mihon treats `all`-language sources as
                                // always visible regardless of the language
                                // filter.
                                (e.lang.toLowerCase() == 'all' ||
                                        enabledLangs
                                            .contains(e.lang.toLowerCase())) &&
                                !disabledIds.contains(e.id))
                            .toList(growable: false);
                    return _buildList(
                      context,
                      ref,
                      extensions,
                      localRoot,
                      pinnedIds: pinnedIds,
                      sourcePrefs: sourcePrefs,
                      filtered: sourcePrefs != null &&
                          extensions.length != allExtensions.length,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<InstalledExtension> extensions,
    String? localRoot, {
    required bool filtered,
    Set<String> pinnedIds = const <String>{},
    SourcePreferences? sourcePrefs,
  }) {
    final pinned = [
      for (final e in extensions)
        if (pinnedIds.contains(e.id)) e,
    ];
    final unpinned = [
      for (final e in extensions)
        if (!pinnedIds.contains(e.id)) e,
    ];
    return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Local source'),
              subtitle: Text(
                localRoot ?? 'Tap to choose a folder of manga on this device.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: localRoot == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Change folder',
                      onPressed: () => _pickLocalRoot(context, ref),
                    ),
              onTap: () async {
                if (localRoot == null) {
                  await _pickLocalRoot(context, ref);
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const SourceBrowseScreen(sourceId: LocalSource.sourceId),
                  ),
                );
              },
            ),
            if (extensions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No other sources installed. Install an extension on '
                  'the Extensions tab to browse online manga.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (pinned.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Pinned',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final e in pinned)
                _SourceTile(
                  extension: e,
                  pinned: true,
                  sourcePrefs: sourcePrefs,
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'All',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            for (final e in unpinned)
              _SourceTile(
                extension: e,
                pinned: false,
                sourcePrefs: sourcePrefs,
              ),
            if (filtered)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Text(
                  'Some sources are hidden by your filter. Tap the '
                  'funnel icon above to adjust.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
  }
}

Future<void> _pickLocalRoot(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Choose your local manga folder',
  );
  if (picked == null) return;
  final prefs = await ref.read(localSourcePreferencesProvider.future);
  await prefs.setRoot(picked);
  // Bust the FutureProvider cache so the tile re-reads the new root.
  ref.invalidate(localSourcePreferencesProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Local folder set to $picked')),
  );
}

class _ExtensionsTab extends ConsumerStatefulWidget {
  const _ExtensionsTab();

  @override
  ConsumerState<_ExtensionsTab> createState() => _ExtensionsTabState();
}

class _ExtensionsTabState extends ConsumerState<_ExtensionsTab> {
  @override
  void initState() {
    super.initState();
    // Probe origins for newer version_codes once per session — the JS
    // model's stand-in for Kotlin's periodic ExtensionUpdateJob. Drives
    // the Browse nav badge + the per-row "Update available" affordance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runExtensionUpdateCheck(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(extensionRepositoryProvider);
    final updatable = ref.watch(extensionUpdatesProvider);
    return Scaffold(
      body: StreamBuilder<List<InstalledExtension>>(
        stream: repo.watchInstalled(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final extensions = snap.data!;
          final incognitoExtensions = ref.watch(incognitoExtensionsProvider);
          if (extensions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No extensions installed. Tap the + button to add one '
                  'from a file or URL.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: extensions.length,
            itemBuilder: (_, i) {
              final e = extensions[i];
              final canUpdate = e.installUrl != null;
              final hasUpdate = updatable.contains(e.id);
              final incognito = incognitoExtensions.contains(e.id);
              return ListTile(
                title: Text(e.name),
                subtitle: Text(
                  '${e.lang.toUpperCase()} • v${e.versionCode}'
                  '${hasUpdate ? ' • Update available' : ''}',
                  style: hasUpdate
                      ? TextStyle(
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        incognito
                            ? Icons.no_encryption_gmailerrorred
                            : Icons.no_encryption_gmailerrorred_outlined,
                      ),
                      color: incognito
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      // Verbatim Mihon string
                      // pref_incognito_mode_extension_summary.
                      tooltip: 'Pause reading history for extension',
                      onPressed: () {
                        final notifier =
                            ref.read(incognitoExtensionsProvider.notifier);
                        final next = {...incognitoExtensions};
                        if (incognito) {
                          next.remove(e.id);
                        } else {
                          next.add(e.id);
                        }
                        notifier.set(next);
                      },
                    ),
                    if (canUpdate)
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: hasUpdate
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        tooltip: hasUpdate
                            ? 'Update available'
                            : 'Update from origin URL',
                        onPressed: () async {
                          await _runUpdate(context, repo, e);
                          clearExtensionUpdate(ref, e.id);
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Uninstall',
                      onPressed: () async {
                        await _confirmUninstall(context, repo, e);
                        clearExtensionUpdate(ref, e.id);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context, repo),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Re-fetches the JS from [e.installUrl] and reinstalls. Surfaces
/// success/failure via SnackBar so the user gets feedback either way.
/// Compares the manifest version code before/after to tell "Updated"
/// vs "Already up to date" — matches Mihon's update flow wording.
Future<void> _runUpdate(
  BuildContext context,
  ExtensionRepository repo,
  InstalledExtension e,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final beforeVersion = e.versionCode;
    final updated = await repo.updateFromOrigin(e);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    final unchanged = updated.versionCode == beforeVersion;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          unchanged
              ? '${updated.name} is already up to date.'
              : 'Updated ${updated.name} '
                  '(v$beforeVersion → v${updated.versionCode}).',
        ),
      ),
    );
  } catch (err) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Update failed: $err')),
    );
  }
}

Future<void> _confirmUninstall(
  BuildContext context,
  ExtensionRepository repo,
  InstalledExtension e,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Uninstall ${e.name}?'),
      content: const Text(
        'The extension and any cached source code will be removed. '
        'Saved manga and history are kept.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Uninstall'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await repo.uninstall(e.id);
  }
}

Future<void> _showAddSheet(
  BuildContext context,
  ExtensionRepository repo,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Install from URL'),
            subtitle: const Text('Paste a raw .js URL'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await _promptForUrl(context, repo);
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Install from file'),
            subtitle: const Text('Pick a .js file from device storage'),
            onTap: () async {
              Navigator.of(ctx).pop();
              await _promptForFile(context, repo);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _promptForUrl(
  BuildContext context,
  ExtensionRepository repo,
) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Install from URL'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'https://...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Install'),
        ),
      ],
    ),
  );
  if (url == null || url.isEmpty) return;
  if (!context.mounted) return;
  await _runInstall(context, () => repo.installFromUrl(url));
}

Future<void> _promptForFile(
  BuildContext context,
  ExtensionRepository repo,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['js'],
  );
  final path = result?.files.singleOrNull?.path;
  if (path == null) return;
  if (!context.mounted) return;
  await _runInstall(context, () => repo.installFromFile(File(path)));
}

Future<void> _runInstall(
  BuildContext context,
  Future<InstalledExtension> Function() install,
) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final extension = await install();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Installed ${extension.name}.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Install failed: $e')),
    );
  }
}

/// Single row in the Sources list. Trailing pin icon flips
/// `pinned_catalogues` membership; pinned rows render above the rest
/// under a "Pinned" header.
class _SourceTile extends ConsumerStatefulWidget {
  const _SourceTile({
    required this.extension,
    required this.pinned,
    required this.sourcePrefs,
  });

  final InstalledExtension extension;
  final bool pinned;
  final SourcePreferences? sourcePrefs;

  @override
  ConsumerState<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends ConsumerState<_SourceTile> {
  /// Whether this extension declares the optional `preferences()` contract
  /// — gates the per-source settings gear (Kotlin only shows the gear for
  /// ConfigurableSource implementations too).
  late bool _hasPrefs = sourcePrefsCapabilityCache[widget.extension.id] ?? false;

  @override
  void initState() {
    super.initState();
    if (!sourcePrefsCapabilityCache.containsKey(widget.extension.id)) {
      _probePrefs();
    }
  }

  Future<void> _probePrefs() async {
    final id = widget.extension.id;
    try {
      final source =
          await ref.read(extensionRepositoryProvider).getSource(id);
      final defs = await source.getPreferences();
      sourcePrefsCapabilityCache[id] = defs.isNotEmpty;
      if (mounted && defs.isNotEmpty) setState(() => _hasPrefs = true);
    } catch (_) {
      // Broken extension — no gear; don't cache so a fixed install retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = widget.extension;
    final pinned = widget.pinned;
    final sourcePrefs = widget.sourcePrefs;
    return ListTile(
      title: Text(extension.name),
      subtitle: Text(extension.lang.toUpperCase()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasPrefs)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Source settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SourcePreferencesScreen(
                      sourceId: extension.id,
                      sourceName: extension.name,
                    ),
                  ),
                );
              },
            ),
          if (sourcePrefs != null)
            IconButton(
              icon: Icon(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: pinned ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: pinned ? 'Unpin' : 'Pin to top',
              onPressed: () => sourcePrefs.toggleSourcePin(extension.id),
            ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SourceBrowseScreen(sourceId: extension.id),
          ),
        );
      },
    );
  }
}
