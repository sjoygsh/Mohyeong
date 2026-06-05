import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk store for user-chosen custom manga covers (Mihon's
/// `CoverCache.getCustomCoverFile`). A custom cover overrides the
/// source-supplied `thumbnailUrl` everywhere the manga's cover is shown
/// in-library. Files live app-internal at:
///   `<appSupport>/covers/custom/<mangaId>`
/// keyed only by manga id (no extension — bytes are written verbatim).
///
/// Lookups must be synchronous because the cover call sites (`SourceImage`)
/// resolve a URL inside `build()`. To allow that, the directory path is
/// resolved once at startup ([create]) and the set of manga ids that already
/// have a custom cover is cached in memory; both are refreshed when a cover
/// is written or removed.
class CoverCache {
  CoverCache._(this._customDirPath, this._haveCustom);

  final String _customDirPath;
  final Set<int> _haveCustom;

  /// Resolve the custom-cover directory and enumerate existing covers so
  /// [hasCustomCover] / [coverUrlFor] can answer synchronously. Called once
  /// from `main()` before the first frame.
  static Future<CoverCache> create() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'covers', 'custom'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final have = <int>{};
    await for (final entry in dir.list()) {
      if (entry is File) {
        final id = int.tryParse(p.basename(entry.path));
        if (id != null) have.add(id);
      }
    }
    return CoverCache._(dir.path, have);
  }

  File customCoverFile(int mangaId) =>
      File(p.join(_customDirPath, mangaId.toString()));

  bool hasCustomCover(int mangaId) => _haveCustom.contains(mangaId);

  /// The cover URL/path to render for [mangaId]: the on-disk custom cover
  /// when one exists, otherwise the source [thumbnailUrl]. Synchronous so it
  /// can be called from widget `build()` methods.
  String? coverUrlFor(int mangaId, String? thumbnailUrl) {
    if (_haveCustom.contains(mangaId)) {
      return customCoverFile(mangaId).path;
    }
    return thumbnailUrl;
  }

  /// Write [bytes] as the custom cover for [mangaId], evicting any cached
  /// decode of the previous file so cover surfaces repaint with the new art.
  Future<void> setCustomCover(int mangaId, Uint8List bytes) async {
    final file = customCoverFile(mangaId);
    await file.writeAsBytes(bytes, flush: true);
    _haveCustom.add(mangaId);
    await FileImage(file).evict();
  }

  /// Remove the custom cover for [mangaId] (revert to the source thumbnail).
  Future<void> deleteCustomCover(int mangaId) async {
    final file = customCoverFile(mangaId);
    if (await file.exists()) await file.delete();
    _haveCustom.remove(mangaId);
    await FileImage(file).evict();
  }
}

/// Resolve [provider] to a single decoded frame and re-encode it as PNG.
/// Used to capture the current reader page's bitmap as custom-cover bytes,
/// uniformly across every backend (`SourceImage` provider: network / file /
/// archive / SAF) since it operates on the decoded image rather than the
/// original byte stream.
Future<Uint8List?> encodeImageProviderToPng(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

final coverCacheProvider = Provider<CoverCache>((ref) {
  throw UnimplementedError('coverCacheProvider must be overridden in main()');
});
