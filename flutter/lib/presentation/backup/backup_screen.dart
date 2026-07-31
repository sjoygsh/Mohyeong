/// User-facing backup/restore screen.
///
/// Mirrors the "Data and storage → Backup" section of Mihon's settings.
/// "Create backup" runs [BackupCreator] and uses `file_picker`'s save
/// dialog to let the user pick where to drop the resulting `.tachibk`
/// file. "Restore" reads any picked file (gzipped protobuf or raw
/// protobuf) and applies it via [BackupRestorer]. Files written by Mihon
/// itself are accepted without any per-app discrimination — the codec is
/// wire-compatible.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/pref_tiles.dart';

import '../../data/backup/backup_codec.dart';
import '../../data/backup/backup_creator.dart';
import '../../data/backup/backup_preferences.dart';
import '../../data/backup/backup_restorer.dart';
import '../../data/backup/backup_scheduler.dart';

import '../tide/tide.dart';
import '../util/user_message.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    return PrefScaffold(
      title: 'Backup & restore',
      children: [
          PrefRow(
            icon: Icons.save_outlined,
            title: 'Create backup',
            subtitle: 'A .tachibk file you can restore later, or move to Mihon',
            onTap: _busy ? null : _createBackup,
          ),
          PrefRow(
            icon: Icons.restore_outlined,
            title: 'Restore backup',
            subtitle: 'Reads a .tachibk (Mihon or Mohyeong) and merges it in',
            onTap: _busy ? null : _restoreBackup,
          ),
          const _BackupIntervalTile(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: TideSpinner()),
            ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Text(_statusMessage!, style: TideText.body()),
            ),
        ],
    );
  }

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final backup = await ref.read(backupCreatorProvider).create();
      final bytes = encodeBackup(backup);
      final defaultName =
          'mohyeong-${DateTime.now().toIso8601String().substring(0, 10)}.tachibk';

      // FilePicker.saveFile returns a path on desktop/Android and accepts
      // bytes for direct-write on Android API 30+ via the SAF dialog.
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup',
        fileName: defaultName,
        bytes: bytes,
      );

      if (savedPath == null) {
        _setStatus('Backup cancelled.');
        return;
      }

      // On Android the SAF dialog returns a document URI / pseudo-path
      // (e.g. `/document/primary:foo.tachibk` when saving to the storage
      // root, or a `content://`/`.../tree/...` form) and file_picker has
      // ALREADY written the bytes we passed via the content resolver.
      // Treating that as a real filesystem path and re-opening it threw
      // PathNotFoundException — only fall back to a manual write for a
      // genuine path (desktop, where saveFile doesn't persist bytes).
      final isSafUri = savedPath.startsWith('content://') ||
          savedPath.contains('/document/') ||
          savedPath.contains('/tree/');
      if (!isSafUri) {
        final file = File(savedPath);
        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }

      _setStatus(
        'Saved ${bytes.length ~/ 1024} KB to:\n$savedPath\n\n'
        '${backup.backupManga.length} manga, '
        '${backup.backupCategories.length} categories.',
      );
    } catch (e) {
      _setStatus(userMessage(e, fallback: 'Backup failed.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pick backup file',
        type: FileType.any,
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) {
        _setStatus('Restore cancelled.');
        return;
      }
      final picked = pick.files.first;
      final Uint8List bytes;
      if (picked.bytes != null) {
        bytes = picked.bytes!;
      } else if (picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      } else {
        _setStatus('Could not read the picked file.');
        return;
      }

      final backup = decodeBackup(bytes);
      final result = await ref.read(backupRestorerProvider).restore(backup);

      _setStatus(
        'Restore complete.\n'
        '${result.mangaRestored} manga, '
        '${result.categoriesRestored} categories, '
        '${result.extensionReposRestored} extension repos, '
        '${result.preferencesRestored} preferences, '
        '${result.linksRestored} links.'
        '${result.skippedMangaWithoutSource > 0 ? "\n${result.skippedMangaWithoutSource} entries skipped (errors)." : ""}',
      );
    } catch (e) {
      _setStatus(userMessage(e, fallback: 'Restore failed.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
  }
}

/// "Automatic backup frequency" (Kotlin SettingsDataScreen's backupInterval
/// ListPreference) plus the backup_info / last_auto_backup_info blurb.
/// Changing the value re-registers the periodic workmanager task, like
/// Kotlin's `BackupCreateJob.setupTask(context, it)`.
class _BackupIntervalTile extends ConsumerWidget {
  const _BackupIntervalTile();

  // Verbatim Kotlin entries (off / update_6hour … update_weekly).
  static const _entries = <(int, String)>[
    (0, 'Off'),
    (6, 'Every 6 hours'),
    (12, 'Every 12 hours'),
    (24, 'Daily'),
    (48, 'Every 2 days'),
    (168, 'Weekly'),
  ];

  String _labelFor(int hours) {
    for (final (h, label) in _entries) {
      if (h == hours) return label;
    }
    return 'Off';
  }

  String _lastBackupText(int millis) {
    if (millis <= 0) return 'Last automatically backed up: never';
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Last automatically backed up: '
        '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(backupIntervalProvider);
    final lastBackup = ref.watch(lastAutoBackupProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PrefRow(
          icon: Icons.schedule_outlined,
          title: 'Automatic backup frequency',
          subtitle: _labelFor(interval),
          onTap: () async {
            final picked = await pickPref<int>(
              context,
              title: 'Automatic backup frequency',
              selected: interval,
              options: [
                for (final (hours, label) in _entries) (hours, label),
              ],
            );
            if (picked == null) return;
            await ref.read(backupIntervalProvider.notifier).set(picked);
            await ref.read(backupSchedulerProvider).reschedule(picked);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            // Verbatim Mihon backup_info + last_auto_backup_info.
            'You should keep copies of backups in other places as well. '
            'Backups may contain sensitive data including any stored '
            'passwords; be careful if sharing.\n\n'
            '${_lastBackupText(lastBackup)}',
            style: TideText.caption(size: 12),
          ),
        ),
      ],
    );
  }
}
