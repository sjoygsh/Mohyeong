/// Automatic-backup preferences, ported from Mihon's `BackupPreferences`.
library;

import '../preferences/typed_preferences.dart';

/// "Automatic backup frequency" in hours; 0 = off. Mihon `backup_interval`,
/// default 12.
final backupIntervalProvider = intPref('backup_interval', 12);

/// Epoch millis of the last successful automatic backup. Mihon
/// `lastAutoBackupTimestamp` (app-state key, excluded from backups).
final lastAutoBackupProvider =
    intPref('__APP_STATE_last_auto_backup_timestamp', 0);
