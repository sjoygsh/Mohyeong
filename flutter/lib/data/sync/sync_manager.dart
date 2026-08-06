/// Top-level orchestration: snapshot local state → push/exchange → apply
/// merged result → record last-sync timestamp. Direct port of Mihon's
/// `SyncManager`.
///
/// Two flow shapes:
///
/// 1. **Server-mediated** (SyncYomi): build the local backup → send to
///    the server → server merges authoritatively → apply the returned
///    payload locally.
///
/// 2. **File storage** (WebDAV / Drive / Dropbox): pull whatever blob
///    exists remotely → apply it via `BackupRestorer` (per-row
///    timestamp merge) → build a fresh local backup of the now-merged
///    state → push it back as the new authoritative remote copy.
///
/// All transports throw [SyncException] on failure so callers can surface
/// a stable message in the UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/network/app_http_client.dart';
import '../backup/backup_codec.dart';
import '../backup/backup_creator.dart';
import '../backup/backup_restorer.dart';
import '../backup/models/backup_models.dart';
import 'dropbox_transport.dart';
import 'google_drive_transport.dart';
import 'sync_preferences.dart';
import 'sync_transport.dart';
import 'syncyomi_transport.dart';
import 'webdav_transport.dart';

class SyncManager {
  SyncManager({
    required this.preferences,
    required this.creator,
    required this.restorer,
    required this.http,
  });

  final SyncPreferences preferences;
  final BackupCreator creator;
  final BackupRestorer restorer;
  final AppHttpClient http;

  /// Runs a full bidirectional sync. Returns the number of manga entries
  /// the restore step applied so the UI can show a "synced N items"
  /// snackbar.
  Future<int> sync() async {
    final data = preferences.read();
    if (data.service == SyncService.none) {
      throw SyncException('Sync service not configured');
    }

    final deviceId = await _ensureDeviceId(data);
    final apiKey = await preferences.getApiKey();
    final transport = _buildTransport(data, apiKey);

    final applied = switch (transport) {
      SyncTransportServerMediated() =>
        await _serverMediatedSync(transport, deviceId, data),
      SyncTransportFileStorage() => await _fileStorageSync(transport, data),
    };

    await preferences.setLastSyncTimestamp(
      DateTime.now().millisecondsSinceEpoch,
    );
    return applied;
  }

  Future<int> _serverMediatedSync(
    SyncTransportServerMediated transport,
    String deviceId,
    SyncPreferencesData data,
  ) async {
    final local = await encodeBackupAsync(_select(await creator.create(), data));
    final merged = await transport.exchange(
      local: local,
      lastSyncTimestamp: data.lastSyncTimestamp,
      deviceId: deviceId,
    );
    final result =
        await restorer.restore(_select(await decodeBackupAsync(merged), data));
    return result.mangaRestored;
  }

  /// Honours the "What to sync" selection, in both directions: an entity the
  /// user switched off is neither pushed to the remote nor applied from it.
  ///
  /// The creator and restorer deliberately stay selection-blind — they exist
  /// to move whole backups, and a backup file always carries everything.
  /// This is the one place the selection is enforced.
  Backup _select(Backup backup, SyncPreferencesData data) {
    if (data.syncCategories &&
        data.syncChapters &&
        data.syncTracking &&
        data.syncHistory) {
      return backup;
    }
    return Backup(
      backupManga: [
        for (final m in backup.backupManga)
          m.withSelection(
            chapters: data.syncChapters,
            categories: data.syncCategories,
            tracking: data.syncTracking,
            history: data.syncHistory,
          ),
      ],
      // Per-manga `categories` are indices into this list — the two have to
      // be dropped together or the indices dangle.
      backupCategories:
          data.syncCategories ? backup.backupCategories : const [],
      backupSources: backup.backupSources,
      backupPreferences: backup.backupPreferences,
      backupSourcePreferences: backup.backupSourcePreferences,
      backupExtensionRepo: backup.backupExtensionRepo,
      backupMangaLinks: backup.backupMangaLinks,
    );
  }

  Future<int> _fileStorageSync(
    SyncTransportFileStorage transport,
    SyncPreferencesData data,
  ) async {
    // 1. Pull whatever the remote currently holds and apply it locally
    //    first — this lets BackupRestorer's `lastModifiedAt` merge
    //    resolve per-row conflicts.
    var appliedFromRemote = 0;
    final remote = await transport.pull();
    if (remote != null) {
      final result =
          await restorer.restore(_select(await decodeBackupAsync(remote), data));
      appliedFromRemote = result.mangaRestored;
    }

    // 2. Snapshot the now-merged local state and push it back as the new
    //    authoritative copy.
    final snapshot =
        await encodeBackupAsync(_select(await creator.create(), data));
    await transport.push(snapshot);
    return appliedFromRemote;
  }

  SyncTransport _buildTransport(SyncPreferencesData data, String apiKey) {
    final host = data.host.trimRight().replaceAll(RegExp(r'/+$'), '');
    switch (data.service) {
      case SyncService.none:
        throw SyncException('Sync service not configured');
      case SyncService.syncYomi:
        if (host.isEmpty) throw SyncException('SyncYomi host is empty');
        if (apiKey.isEmpty) throw SyncException('SyncYomi API key is empty');
        return SyncYomiTransport(host: host, apiKey: apiKey, dio: http.dio);
      case SyncService.webDav:
        if (host.isEmpty) throw SyncException('WebDAV URL is empty');
        if (data.username.isEmpty) {
          throw SyncException('WebDAV username is empty');
        }
        if (apiKey.isEmpty) throw SyncException('WebDAV password is empty');
        return WebDavTransport(
          host: host,
          username: data.username,
          password: apiKey,
          dio: http.dio,
        );
      case SyncService.googleDrive:
        if (apiKey.isEmpty) {
          throw SyncException('Google Drive access token is empty');
        }
        return GoogleDriveTransport(accessToken: apiKey, dio: http.dio);
      case SyncService.dropbox:
        if (apiKey.isEmpty) {
          throw SyncException('Dropbox access token is empty');
        }
        return DropboxTransport(accessToken: apiKey, dio: http.dio);
    }
  }

  /// Mihon writes a UUID once and reuses it across syncs so the server
  /// can distinguish devices for the same account.
  Future<String> _ensureDeviceId(SyncPreferencesData data) async {
    if (data.deviceId.isNotEmpty) return data.deviceId;
    // Cheap UUID v4-ish without pulling a new dep: random hex pieces.
    final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
        DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final id = '${rand.padLeft(24, '0').substring(0, 24)}-mohyeong';
    await preferences.write(data.copyWith(deviceId: id));
    return id;
  }
}

final syncManagerProvider = FutureProvider<SyncManager>((ref) async {
  final prefs = await ref.watch(syncPreferencesProvider.future);
  return SyncManager(
    preferences: prefs,
    creator: ref.watch(backupCreatorProvider),
    restorer: ref.watch(backupRestorerProvider),
    http: ref.watch(appHttpClientProvider),
  );
});
