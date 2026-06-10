import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Cache-size accounting and clearing for the "Clear chapter cache" action
/// (Mihon `ChapterCache.readableSize` / `clear()`). The Flutter equivalent of
/// the chapter+image cache is the temp dir: the cached_network_image store
/// (reader pages, covers) plus staged share images all live there.
abstract final class AppCache {
  /// Total size in bytes of everything under the app cache dir.
  static Future<int> sizeBytes() async {
    final dir = await getTemporaryDirectory();
    var total = 0;
    if (!dir.existsSync()) return 0;
    await for (final f in dir.list(recursive: true, followLinks: false)) {
      if (f is File) {
        try {
          total += f.lengthSync();
        } catch (_) {
          // File vanished mid-walk — skip it.
        }
      }
    }
    return total;
  }

  /// Empties the image cache store and deletes everything under the cache
  /// dir. Returns the number of files removed (Mihon's `cache_deleted`
  /// toast count).
  static Future<int> clear() async {
    await DefaultCacheManager().emptyCache();
    final dir = await getTemporaryDirectory();
    var deleted = 0;
    if (!dir.existsSync()) return 0;
    for (final entry in dir.listSync(followLinks: false)) {
      try {
        if (entry is File) {
          entry.deleteSync();
          deleted++;
        } else if (entry is Directory) {
          deleted += entry
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .length;
          entry.deleteSync(recursive: true);
        }
      } catch (_) {
        // Locked entries are skipped, matching Mihon's best-effort clear.
      }
    }
    // Flutter's in-memory decoded-image cache too, so reopened pages
    // actually re-fetch.
    PaintingBinding.instance.imageCache.clear();
    return deleted;
  }

  /// "12.3 MB"-style size formatting (Mihon uses Formatter.formatFileSize).
  static String readableSize(int bytes) {
    const units = ['B', 'kB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1000 && unit < units.length - 1) {
      size /= 1000;
      unit++;
    }
    final text = size >= 100 || unit == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(2);
    return '$text ${units[unit]}';
  }
}
