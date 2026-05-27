import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import 'source_browse_screen.dart';

/// Browse hosts two sub-tabs: Sources (installed sources you can browse) and
/// Extensions (install / uninstall management).
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Browse'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sources'),
              Tab(text: 'Extensions'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SourcesTab(),
            _ExtensionsTab(),
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
    return StreamBuilder<List<InstalledExtension>>(
      stream: repo.watchInstalled(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final extensions = snap.data!;
        if (extensions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No sources installed. Install an extension on the '
                'Extensions tab to browse manga.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: extensions.length,
          itemBuilder: (_, i) {
            final e = extensions[i];
            return ListTile(
              title: Text(e.name),
              subtitle: Text(e.lang.toUpperCase()),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SourceBrowseScreen(sourceId: e.id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ExtensionsTab extends ConsumerWidget {
  const _ExtensionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(extensionRepositoryProvider);
    return Scaffold(
      body: StreamBuilder<List<InstalledExtension>>(
        stream: repo.watchInstalled(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final extensions = snap.data!;
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
              return ListTile(
                title: Text(e.name),
                subtitle: Text('${e.lang.toUpperCase()} • v${e.versionCode}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmUninstall(context, repo, e),
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
