import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/library/library_update_preference.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/source/local_source_preferences.dart';
import '../../data/source/saf.dart';
import '../../data/storage/app_cache.dart';
import '../../domain/manga/model/manga.dart';
import '../backup/backup_screen.dart';
import '../sync/sync_settings_screen.dart';
import 'pref_tiles.dart';

/// Data & storage sub-screen: storage location + backup/restore + sync.
/// Mirrors the "Data and storage" section of Mihon's settings.
class DataStorageSettingsScreen extends StatelessWidget {
  const DataStorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data and storage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Guide',
            onPressed: () => launchUrl(
              Uri.parse('https://sjoygsh.github.io/Mohyeong/help.html#storage'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          const _StorageLocationTile(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Used for automatic backups, chapter downloads, and local '
              'source.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Backup & restore'),
            subtitle: const Text('Mihon-compatible .tachibk export/import'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BackupScreen(),
              ),
            ),
          ),
          ListTile(
            title: const Text('Sync'),
            subtitle:
                const Text('SyncYomi, WebDAV, Google Drive, or Dropbox'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SyncSettingsScreen(),
              ),
            ),
          ),

          // ── Storage usage (Kotlin getDataGroup) ─────────────────────
          const PrefSectionHeader('Storage usage'),
          const _StorageUsageBar(),
          const _ClearCacheTile(),
          const _AutoClearCacheSwitch(),

          // ── Export (Kotlin getExportGroup) ──────────────────────────
          const PrefSectionHeader('Export'),
          const _ExportLibraryTile(),
        ],
      ),
    );
  }
}

/// Kotlin `StorageInfo`: a bar of the data volume's usage with
/// "Available: X / Total: Y" beneath it.
class _StorageUsageBar extends StatefulWidget {
  const _StorageUsageBar();

  @override
  State<_StorageUsageBar> createState() => _StorageUsageBarState();
}

class _StorageUsageBarState extends State<_StorageUsageBar> {
  (int, int)? _stats;

  @override
  void initState() {
    super.initState();
    Saf.storageStats().then((s) {
      if (mounted) setState(() => _stats = s);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final (available, total) = stats;
    final used = (total - available).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : used / total,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          // Verbatim Mihon string available_disk_space_info.
          Text(
            'Available: ${AppCache.readableSize(available)} / '
            'Total: ${AppCache.readableSize(total)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Kotlin "Clear chapter cache" with the "Used: X" subtitle and the
/// "Cache cleared, N files deleted" toast.
class _ClearCacheTile extends StatefulWidget {
  const _ClearCacheTile();

  @override
  State<_ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends State<_ClearCacheTile> {
  int? _sizeBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final size = await AppCache.sizeBytes();
    if (mounted) setState(() => _sizeBytes = size);
  }

  Future<void> _clear() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await AppCache.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('Cache cleared, $deleted files deleted')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Error occurred while clearing')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Clear chapter cache'),
      subtitle: Text(
        _sizeBytes == null
            ? 'Used: …'
            : 'Used: ${AppCache.readableSize(_sizeBytes!)}',
      ),
      enabled: !_clearing,
      onTap: _clear,
    );
  }
}

class _AutoClearCacheSwitch extends ConsumerWidget {
  const _AutoClearCacheSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Verbatim Mihon string pref_auto_clear_chapter_cache.
    return SwitchListTile(
      title: const Text('Clear chapter cache on app launch'),
      value: ref.watch(autoClearChapterCacheProvider),
      onChanged: ref.read(autoClearChapterCacheProvider.notifier).set,
    );
  }
}

/// Kotlin getExportGroup: "Library List" → column-selection dialog →
/// CSV save. CSV format matches LibraryExporter.generateCsvData exactly
/// (no header row, CRLF separators, RFC-style quoting).
class _ExportLibraryTile extends ConsumerWidget {
  const _ExportLibraryTile();

  static final _escapeRequired = ['\r', '\n', '"', ','];

  static String _csv(List<Manga> favorites, bool author, bool artist) {
    final rows = <String>[];
    for (final manga in favorites) {
      final columns = <String?>[
        manga.title,
        if (author) manga.author,
        if (artist) manga.artist,
      ];
      rows.add(columns.map((column) {
        if (column == null || column.trim().isEmpty) return '';
        if (_escapeRequired.any(column.contains)) {
          return '"${column.replaceAll('"', '""')}"';
        }
        return column;
      }).join(','));
    }
    return rows.join('\r\n');
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final options = await showDialog<(bool, bool)>(
      context: context,
      builder: (ctx) => const _ColumnSelectionDialog(),
    );
    if (options == null) return;
    final (author, artist) = options;
    final favorites = await ref.read(mangaRepositoryProvider).getFavorites();
    final csv = _csv(favorites, author, artist);
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: 'Export library list',
      fileName: 'mohyeong_library.csv',
      bytes: utf8.encode(csv),
    );
    if (saved == null) return;
    // Verbatim Mihon string library_exported.
    messenger.showSnackBar(
      const SnackBar(content: Text('Library Exported')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: const Text('Library List'),
      onTap: () => _export(context, ref),
    );
  }
}

/// Kotlin ColumnSelectionDialog: Title is mandatory in spirit — unchecking
/// it clears and disables Author/Artist. Returns (includeAuthor,
/// includeArtist); Title is always exported when confirmed, matching the
/// Kotlin default flow.
class _ColumnSelectionDialog extends StatefulWidget {
  const _ColumnSelectionDialog();

  @override
  State<_ColumnSelectionDialog> createState() => _ColumnSelectionDialogState();
}

class _ColumnSelectionDialogState extends State<_ColumnSelectionDialog> {
  bool _title = true;
  bool _author = true;
  bool _artist = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select data to include'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Title'),
            value: _title,
            onChanged: (v) => setState(() {
              _title = v ?? false;
              if (!_title) {
                _author = false;
                _artist = false;
              }
            }),
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Author'),
            value: _author,
            onChanged: _title
                ? (v) => setState(() => _author = v ?? false)
                : null,
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Artist'),
            value: _artist,
            onChanged: _title
                ? (v) => setState(() => _artist = v ?? false)
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed:
              _title ? () => Navigator.of(context).pop((_author, _artist)) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The storage-location row, equivalent to Mihon's `storageLocationPicker` /
/// `storageLocationText` in SettingsDataScreen. Tapping launches the system
/// folder picker (SAF) and persists the chosen tree URI to
/// `__APP_STATE_storage_dir`.
class _StorageLocationTile extends ConsumerStatefulWidget {
  const _StorageLocationTile();

  @override
  ConsumerState<_StorageLocationTile> createState() =>
      _StorageLocationTileState();
}

class _StorageLocationTileState extends ConsumerState<_StorageLocationTile> {
  String? _displayName;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _refreshName();
  }

  Future<void> _refreshName() async {
    final uri = ref.read(storageDirProvider);
    if (uri == null) {
      if (mounted) setState(() => _displayName = null);
      return;
    }
    final name = Saf.isContentUri(uri) ? await Saf.displayName(uri) : uri;
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final uri = await Saf.openTree();
      if (uri != null) {
        await ref.read(storageDirProvider.notifier).set(uri);
        await _refreshName();
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = ref.watch(storageDirProvider);
    return ListTile(
      leading: _picking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.folder_outlined),
      title: const Text('Storage location'),
      subtitle: Text(
        uri == null ? 'No storage location set' : (_displayName ?? uri),
      ),
      onTap: _picking ? null : _pick,
    );
  }
}
