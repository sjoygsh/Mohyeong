/// Dart facade over the native Storage Access Framework MethodChannel
/// (`app.mohyeong/saf`, handled in MainActivity.kt).
///
/// Android scoped storage (API 29+) forbids the raw `dart:io` directory
/// access the Local source used to rely on. Instead the user grants a
/// persistable tree permission via the system folder picker
/// (`ACTION_OPEN_DOCUMENT_TREE`), exactly as Mihon does, and we walk that
/// tree through `DocumentsContract` on the native side. Everything here
/// deals in `content://` document URIs, never filesystem paths.
library;

import 'package:flutter/services.dart';

/// One entry (file or sub-folder) inside a SAF tree.
class SafEntry {
  const SafEntry({
    required this.name,
    required this.uri,
    required this.isDir,
    required this.size,
    required this.mime,
  });

  /// Display name (the file/folder's own name, not a path).
  final String name;

  /// Tree-based `content://` document URI — pass back to [Saf.listChildren]
  /// or [Saf.readBytes].
  final String uri;

  final bool isDir;
  final int size;
  final String mime;

  factory SafEntry.fromMap(Map<dynamic, dynamic> map) => SafEntry(
        name: map['name'] as String? ?? '',
        uri: map['uri'] as String? ?? '',
        isDir: map['isDir'] as bool? ?? false,
        size: (map['size'] as num?)?.toInt() ?? 0,
        mime: map['mime'] as String? ?? '',
      );
}

class Saf {
  Saf._();

  static const MethodChannel _channel = MethodChannel('app.mohyeong/saf');

  /// Returns true when `content://` URIs should be routed through this
  /// channel. The native handler only exists on Android; on other platforms
  /// the Local source falls back to `dart:io` paths.
  static bool isContentUri(String uri) => uri.startsWith('content://');

  /// Launches the system folder picker and takes a persistable
  /// read+write permission on the chosen tree. Resolves to the tree URI
  /// string, or null if the user cancelled.
  static Future<String?> openTree() =>
      _channel.invokeMethod<String>('openTree');

  /// Lists the immediate children of a tree URI (root) or a tree-based
  /// document URI (sub-folder).
  static Future<List<SafEntry>> listChildren(String uri) async {
    final raw = await _channel
        .invokeMethod<List<dynamic>>('listChildren', {'uri': uri});
    if (raw == null) return const [];
    return raw
        .map((e) => SafEntry.fromMap(e as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  /// Reads the full bytes of a document URI (an image page or cover).
  static Future<Uint8List?> readBytes(String uri) =>
      _channel.invokeMethod<Uint8List>('readBytes', {'uri': uri});

  /// Best-effort human-readable name for a tree URI, for display in
  /// settings / onboarding.
  static Future<String?> displayName(String uri) =>
      _channel.invokeMethod<String>('displayName', {'uri': uri});

  /// Whether a persisted permission for [uri] still exists. The user can
  /// revoke it from Android system settings, so the Storage step re-checks.
  static Future<bool> hasPermission(String uri) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'uri': uri}) ?? false;

  /// `(available, total)` bytes of the volume holding the app's data dir —
  /// backs the "Storage usage" bar (Mihon's StorageInfo).
  static Future<(int, int)?> storageStats() async {
    final raw =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('storageStats');
    if (raw == null) return null;
    final available = raw['available'] as int?;
    final total = raw['total'] as int?;
    if (available == null || total == null || total <= 0) return null;
    return (available, total);
  }
}
