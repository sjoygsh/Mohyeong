import '../manga/excluded_scanlators_repository.dart';
import '../manga/scanlator_priority_repository.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../background/workmanager_tasks.dart';
import '../category/category_repository.dart';
import '../chapter/chapter_repository.dart';
import '../database/app_database.dart';
import '../history/history_repository.dart';
import '../manga/manga_repository.dart';
import '../source/source_repository.dart';
import '../track/track_repository.dart';
import 'backup_codec.dart';
import 'backup_creator.dart';

/// Identifier of the periodic auto-backup task (Mihon `BackupCreateJob`
/// TAG_AUTO equivalent).
const String backupTaskName = 'mohyeong.backup';

/// Auto-backup filenames: `mohyeong_auto_2026-06-11_14-30.tachibk`. The
/// prefix scopes the retention trim to automatic backups only, like Mihon's
/// FILENAME_REGEX.
final RegExp _autoBackupName =
    RegExp(r'^mohyeong_auto_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\.tachibk$');

/// Mihon `BackupCreator.MAX_AUTO_BACKUPS`.
const int _maxAutoBackups = 4;

/// Directory automatic backups land in. Mihon writes into the user storage
/// dir's `backup/` folder via SAF; the Flutter SAF wrapper is read-only, so
/// autos live under the app documents dir instead (still included in the
/// restore picker via the normal file picker).
Future<Directory> autoBackupDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}${Platform.pathSeparator}backup');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// Creates one automatic backup inside the background isolate: builds the
/// creator from scratch (no Riverpod there), trims older autos down to
/// [_maxAutoBackups], writes the new file, and stamps
/// `last_auto_backup_timestamp`. Mirrors `BackupCreateJob.doWork` +
/// `BackupCreator.backup(isAutoBackup = true)`.
Future<bool> runBackupTask() async {
  try {
    final db = AppDatabase();
    try {
      final creator = BackupCreator(
        database: db,
        mangaRepository: MangaRepository(db),
        chapterRepository: ChapterRepository(db),
        categoryRepository: CategoryRepository(db),
        historyRepository: HistoryRepository(db),
        trackRepository: TrackRepository(db),
        sourceRepository: SourceRepository(db),
        excludedScanlatorsRepository: ExcludedScanlatorsRepository(db),
        scanlatorPriorityRepository: ScanlatorPriorityRepository(db),
      );
      final bytes = await encodeBackupAsync(await creator.create());

      final dir = await autoBackupDirectory();
      // Delete older autos so at most MAX_AUTO_BACKUPS remain after this
      // write (Kotlin: sortedByDescending(name).drop(MAX - 1).delete()).
      final existing = dir
          .listSync()
          .whereType<File>()
          .where((f) => _autoBackupName.hasMatch(f.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final old in existing.skip(_maxAutoBackups - 1)) {
        try {
          old.deleteSync();
        } catch (_) {
          // Best effort — a locked file shouldn't fail the backup.
        }
      }

      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'mohyeong_auto_${now.year}-${two(now.month)}-'
          '${two(now.day)}_${two(now.hour)}-${two(now.minute)}.tachibk';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setInt(
        '__APP_STATE_last_auto_backup_timestamp',
        now.millisecondsSinceEpoch,
      );
    } finally {
      await db.close();
    }
    return true;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('auto-backup task failed: $e\n$st');
    }
    return false;
  }
}

/// UI-side façade over the auto-backup workmanager registration. 1:1 with
/// `BackupCreateJob.setupTask`: a periodic task at the configured interval
/// with the battery-not-low constraint, cancelled when the interval is 0.
class BackupScheduler {
  BackupScheduler();

  Future<void> reschedule(int intervalHours) async {
    await ensureWorkmanagerInitialized();
    await Workmanager().cancelByUniqueName(backupTaskName);
    if (intervalHours <= 0) return;
    await Workmanager().registerPeriodicTask(
      backupTaskName,
      backupTaskName,
      frequency: Duration(hours: intervalHours),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}

final backupSchedulerProvider =
    Provider<BackupScheduler>((ref) => BackupScheduler());
