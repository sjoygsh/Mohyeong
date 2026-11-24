import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk cover stores, Mihon's `CoverCache`:
///
///  * Custom covers the user chose (`getCustomCoverFile`), at
///    `<appSupport>/covers/custom/<mangaId>`, which override the source's
///    thumbnail everywhere.
///  * LIBRARY covers (`getCoverFile`), at `<appSupport>/covers/<md5(url)>`:
///    the source thumbnail of every series in the library, kept for good.
///    Before this, library covers lived only in the shared image cache with
///    the reader's pages, which expires entries after 30 days and holds 2000
///    files, so reading a couple of dozen chapters or leaving the app for a
///    month pushed every cover out and the library reloaded them all from the
///    network, blank until each arrived. Mihon keeps them apart for exactly
///    that reason; [MangaCoverFetcher] reads this file first and only goes to
///    the network when it is missing.
///
/// Lookups must be synchronous because the cover call sites (`SourceImage`)
/// resolve a URL inside `build()`. The directories are resolved once at
/// startup ([create]); custom covers are enumerated then, and library covers
/// are checked once per URL and remembered.
class CoverCache {
  CoverCache._(this._customDirPath, this._libraryDirPath, this._haveCustom);

  /// For tests: both stores rooted at [root], nothing enumerated.
  @visibleForTesting
  CoverCache.forTesting(String root)
      : _customDirPath = p.join(root, 'custom'),
        _libraryDirPath = root,
        _haveCustom = <int>{};

  final String _customDirPath;
  final String _libraryDirPath;
  final Set<int> _haveCustom;

  /// Library-cover presence by thumbnail URL, so a grid rebuild never stats
  /// the same file twice. Kept current by [storeLibraryCover] and the deletes.
  final Map<String, bool> _haveLibrary = <String, bool>{};

  /// The one instance, for the data layer (a refresh that changes a
  /// thumbnail URL drops the old file, as Mihon's `UpdateManga` does) which
  /// has no Riverpod container. Set by [create].
  static CoverCache? instance;

  /// Resolve the cover directories and enumerate existing custom covers so
  /// [hasCustomCover] / [coverUrlFor] can answer synchronously. Called once
  /// from `main()` before the first frame.
  static Future<CoverCache> create() async {
    final support = await getApplicationSupportDirectory();
    final library = Directory(p.join(support.path, 'covers'));
    final dir = Directory(p.join(library.path, 'custom'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final have = <int>{};
    await for (final entry in dir.list()) {
      if (entry is File) {
        final id = int.tryParse(p.basename(entry.path));
        if (id != null) have.add(id);
      }
    }
    return instance = CoverCache._(dir.path, library.path, have);
  }

  File customCoverFile(int mangaId) =>
      File(p.join(_customDirPath, mangaId.toString()));

  bool hasCustomCover(int mangaId) => _haveCustom.contains(mangaId);

  /// Where the library cover for [thumbnailUrl] lives (Mihon names it by the
  /// URL's md5, so a series whose source changes its cover gets a new file).
  String libraryCoverPath(String thumbnailUrl) => p.join(
        _libraryDirPath,
        md5.convert(utf8.encode(thumbnailUrl)).toString(),
      );

  bool hasLibraryCover(String thumbnailUrl) =>
      _haveLibrary[thumbnailUrl] ??=
          File(libraryCoverPath(thumbnailUrl)).existsSync();

  /// The cover URL/path to render for [mangaId]: the on-disk custom cover
  /// when one exists, then a stored library cover for [thumbnailUrl],
  /// otherwise the URL itself. Synchronous so it can be called from widget
  /// `build()` methods.
  ///
  /// The library file is used whenever it exists, without asking whether the
  /// series is in the library: only library series ever get one, it is
  /// deleted when the series leaves (see [removeCovers]), and it is named by
  /// the URL, so it is always that exact image. That lets every cover surface
  /// (grids, History, Updates, the series page) share it without each one
  /// having to know the favourite flag.
  String? coverUrlFor(int mangaId, String? thumbnailUrl) {
    if (_haveCustom.contains(mangaId)) {
      return customCoverFile(mangaId).path;
    }
    if (thumbnailUrl != null &&
        thumbnailUrl.startsWith('http') &&
        hasLibraryCover(thumbnailUrl)) {
      return libraryCoverPath(thumbnailUrl);
    }
    return thumbnailUrl;
  }

  /// Where a library series' cover should be saved once it loads, or null
  /// when it needs no saving: not in the library, not a web cover, already
  /// stored, or overridden by a custom cover.
  String? libraryCoverTarget(
    int mangaId,
    String? thumbnailUrl, {
    required bool favorite,
  }) {
    if (!favorite || _haveCustom.contains(mangaId)) return null;
    if (thumbnailUrl == null || !thumbnailUrl.startsWith('http')) return null;
    if (hasLibraryCover(thumbnailUrl)) return null;
    return libraryCoverPath(thumbnailUrl);
  }

  /// Drop the stored library cover for [thumbnailUrl], if any.
  Future<bool> deleteLibraryCover(String? thumbnailUrl) async {
    if (thumbnailUrl == null || !thumbnailUrl.startsWith('http')) return false;
    _haveLibrary[thumbnailUrl] = false;
    final file = File(libraryCoverPath(thumbnailUrl));
    if (!await file.exists()) return false;
    await file.delete();
    await FileImage(file).evict();
    return true;
  }

  /// Delete every stored library cover (custom covers are kept). Backs
  /// Advanced > Clear cover cache, whose promise is that thumbnails come back
  /// from the source; they are re-saved as they load. Returns files deleted.
  Future<int> clearLibraryCovers() async {
    _haveLibrary.clear();
    var deleted = 0;
    final dir = Directory(_libraryDirPath);
    if (!await dir.exists()) return 0;
    await for (final entry in dir.list(followLinks: false)) {
      // Only the flat md5-named files; `custom/` is a sibling directory.
      if (entry is! File) continue;
      try {
        await entry.delete();
        deleted++;
      } catch (_) {}
    }
    PaintingBinding.instance.imageCache.clear();
    return deleted;
  }

  /// Mihon's `Manga.removeCovers`, run when a series leaves the library: its
  /// library cover AND its custom cover go.
  Future<void> removeCovers(int mangaId, String? thumbnailUrl) async {
    await deleteLibraryCover(thumbnailUrl);
    if (_haveCustom.contains(mangaId)) await deleteCustomCover(mangaId);
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

/// Save a loaded cover into the library store at [target] (a path from
/// [CoverCache.libraryCoverTarget]), from the file it was loaded from or the
/// bytes the WebView handed back. Written beside the target and renamed into
/// place, so a cover cut off half-written is never read back as an image.
/// Best-effort: a cover that fails to save just loads from the network again.
Future<void> storeLibraryCover(
  String target, {
  String? fromPath,
  Uint8List? bytes,
}) async {
  final tmp = File('$target.part');
  try {
    if (fromPath != null) {
      await File(fromPath).copy(tmp.path);
    } else if (bytes != null && bytes.isNotEmpty) {
      await tmp.writeAsBytes(bytes, flush: true);
    } else {
      return;
    }
    await tmp.rename(target);
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
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
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    // Each listener gets its OWN clone of the decoded image and owns it. The
    // reader resolves pages here at full resolution for Set as cover / Share
    // / Copy / Save, so every one of those actions used to strand a 10-15MB
    // native bitmap for the rest of the session. Elsewhere in the codebase
    // this is already handled — crop_borders_image and _resolvePageAspect
    // both dispose with a comment saying why; this was the one that didn't.
    image.dispose();
  }
}

final coverCacheProvider = Provider<CoverCache>((ref) {
  throw UnimplementedError('coverCacheProvider must be overridden in main()');
});
