/// Wire abstraction for the four supported sync backends.
///
/// Mirrors Mihon's `SyncTransport` sealed interface:
///
/// - [SyncTransportServerMediated]: SyncYomi-style backend that receives
///   the local snapshot, performs the authoritative merge server-side,
///   and returns the merged payload to apply locally.
///
/// - [SyncTransportFileStorage]: dumb blob store (WebDAV / Google Drive
///   / Dropbox). The client pulls whatever payload exists, applies it
///   locally (using [BackupRestorer]'s per-row `lastModifiedAt` merge)
///   and pushes the merged snapshot back.
///
/// Payloads stay as [Uint8List] in Dart because typical libraries fit
/// comfortably in memory; streaming-off-disk like Mihon does with OkHttp
/// only matters for huge backups, and we can revisit it via dio's
/// `ResponseType.stream` if real users hit a wall.
library;

import 'dart:typed_data';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => 'SyncException: $message';
}

sealed class SyncTransport {
  const SyncTransport();
}

abstract class SyncTransportServerMediated extends SyncTransport {
  const SyncTransportServerMediated();

  /// Upload the local snapshot and receive the merged payload to apply.
  Future<Uint8List> exchange({
    required Uint8List local,
    required int lastSyncTimestamp,
    required String deviceId,
  });
}

abstract class SyncTransportFileStorage extends SyncTransport {
  const SyncTransportFileStorage();

  /// Returns the remote payload, or null if no remote file exists yet.
  Future<Uint8List?> pull();

  /// Uploads the merged snapshot, replacing the current remote copy.
  Future<void> push(Uint8List payload);
}
