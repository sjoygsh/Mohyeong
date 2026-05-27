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

import '../../data/backup/backup_codec.dart';
import '../../data/backup/backup_creator.dart';
import '../../data/backup/backup_restorer.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('Create backup'),
            subtitle: const Text(
              'Saves a .tachibk file you can restore later or move to Mihon.',
            ),
            enabled: !_busy,
            onTap: _createBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restore backup'),
            subtitle: const Text(
              'Reads a .tachibk file (Mihon or Mohyeong) and merges it into '
              'your library.',
            ),
            enabled: !_busy,
            onTap: _restoreBackup,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
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

      // On platforms where saveFile only returned the destination path
      // (not actually wrote bytes), fall back to writing it ourselves.
      final file = File(savedPath);
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }

      _setStatus(
        'Saved ${bytes.length ~/ 1024} KB to:\n$savedPath\n\n'
        '${backup.backupManga.length} manga, '
        '${backup.backupCategories.length} categories.',
      );
    } catch (e) {
      _setStatus('Backup failed: $e');
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
        '${result.preferencesRestored} preferences.'
        '${result.skippedMangaWithoutSource > 0 ? "\n${result.skippedMangaWithoutSource} entries skipped (errors)." : ""}',
      );
    } catch (e) {
      _setStatus('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
  }
}
