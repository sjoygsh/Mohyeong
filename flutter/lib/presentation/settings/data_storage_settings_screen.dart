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
import '../tide/tide.dart';
import 'pref_tiles.dart';

/// Data & storage sub-screen: storage location + backup/restore + sync.
/// Mirrors the "Data and storage" section of Mihon's settings.
class DataStorageSettingsScreen extends StatelessWidget {
  const DataStorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PrefScaffold(
      title: 'Data and storage',
      actions: [
        TideIconButton(
          icon: Icons.help_outline,
          onTap: () => launchUrl(
            Uri.parse('https://sjoygsh.github.io/Mohyeong/help.html#storage'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
      children: [
          const _StorageLocationTile(),
          const PrefNote(
            'Used for automatic backups, chapter downloads, and the local '
            'source.',
          ),
          PrefRow(
            icon: Icons.settings_backup_restore,
            title: 'Backup & restore',
            subtitle: 'Mihon-compatible .tachibk export/import',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BackupScreen(),
              ),
            ),
          ),
          PrefRow(
            icon: Icons.sync,
            title: 'Sync',
            subtitle: 'SyncYomi, WebDAV, Google Drive, or Dropbox',
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
    return PrefRow(
      icon: Icons.cleaning_services_outlined,
      title: 'Clear chapter cache',
      subtitle: _sizeBytes == null
          ? 'Used: …'
          : 'Used: ${AppCache.readableSize(_sizeBytes!)}',
      onTap: _clearing ? null : _clear,
    );
  }
}

class _AutoClearCacheSwitch extends ConsumerWidget {
  const _AutoClearCacheSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Verbatim Mihon string pref_auto_clear_chapter_cache.
    return PrefSwitchRaw(
      title: 'Clear chapter cache on app launch',
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
    final options = await showTideSheet<(bool, bool)>(
      context,
      (_) => const _ColumnSelectionDialog(),
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
    return PrefRow(
      icon: Icons.table_chart_outlined,
      title: 'Library List',
      subtitle: 'Export titles, authors and artists as CSV',
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
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select data to include', style: TideText.display(21)),
          const SizedBox(height: 18),
          TideCheck(
            label: 'Title',
            value: _title,
            onChanged: (v) => setState(() {
              _title = v;
              if (!_title) {
                _author = false;
                _artist = false;
              }
            }),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: _title ? 1 : 0.45,
            child: TideCheck(
              label: 'Author',
              value: _author,
              onChanged: (v) {
                if (_title) setState(() => _author = v);
              },
            ),
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: _title ? 1 : 0.45,
            child: TideCheck(
              label: 'Artist',
              value: _artist,
              onChanged: (v) {
                if (_title) setState(() => _artist = v);
              },
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: _title ? 1 : 0.4,
                  child: TideButton(
                    label: 'Save',
                    primary: true,
                    onTap: () {
                      if (!_title) return;
                      Navigator.of(context).pop((_author, _artist));
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
