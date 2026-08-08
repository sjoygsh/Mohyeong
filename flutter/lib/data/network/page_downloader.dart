import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Fetches reader pages on a **background isolate** and hands back a file path.
///
/// This exists because of a measurement, not a hunch. Scrolling a cold chapter
/// delivered 22-25fps with 94-100% of frames skipping a display refresh, while
/// each frame cost 0.4ms to build and 2.3ms to raster — the frames were cheap
/// and *late*, with `vsync-wait` sitting at 17ms. The same chapter scrolled at
/// a flat 59.9fps with 0% skipped once its images were on disk, with the image
/// cache emptied so every page still had to be decoded from scratch. Identical
/// decode work, perfectly smooth. That leaves exactly one culprit: the fetch.
///
/// `flutter_cache_manager` streams the HTTP response and writes the file on the
/// UI isolate. A multi-megabyte webtoon page is a flood of chunk events and
/// large `Uint8List` allocations on the one thread that also has to start
/// frames, so it stops starting them on time. Mihon never hits this because
/// OkHttp downloads and writes on IO threads.
///
/// So reader pages get their own store and their own isolate. Covers and browse
/// grids are small and stay on `appImageCacheManager` — nothing outside the
/// reader changes.
abstract final class PageDownloader {
  /// One isolate is enough: [PageFetchQueue] already serialises reader pages to
  /// a single in-flight fetch, so there is never a second download to overlap.
  static Isolate? _isolate;
  static SendPort? _tx;
  static ReceivePort? _rx;
  static Future<void>? _booting;

  static final Map<int, Completer<void>> _pending = <int, Completer<void>>{};
  static int _nextId = 0;

  static String? _dir;

  /// Directory for the page store, under the app cache dir so
  /// `AppCache.sizeBytes` counts it and "Clear chapter cache" removes it —
  /// both already walk the temp dir recursively.
  static Future<String> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final tmp = await getTemporaryDirectory();
    final dir = '${tmp.path}/mohyeong_pages';
    await Directory(dir).create(recursive: true);
    return _dir = dir;
  }

  /// Stable per-URL filename. MD5 rather than `String.hashCode`, which Dart
  /// does not guarantee across runs — a cache whose keys move between launches
  /// is not a cache.
  static String _fileName(String url) =>
      md5.convert(utf8.encode(url)).toString();

  /// The stored path for [url] if it is already on disk, else null. One `stat`,
  /// no bytes read.
  static Future<String?> cachedPath(String url) async {
    final path = '${await _directory()}/${_fileName(url)}';
    return await File(path).exists() ? path : null;
  }

  /// Downloads [url] into the store and returns its path. Throws on failure so
  /// the caller can fall through to the WebView path.
  static Future<String> fetch(String url, Map<String, String>? headers) async {
    final dest = '${await _directory()}/${_fileName(url)}';
    if (await File(dest).exists()) return dest;
    await _ensureStarted();
    final id = _nextId++;
    final done = Completer<void>();
    _pending[id] = done;
    _tx!.send(<String, Object?>{
      'id': id,
      'url': url,
      'headers': headers,
      'dest': dest,
    });
    await done.future;
    return dest;
  }

  static Future<void> _ensureStarted() {
    if (_tx != null) return Future<void>.value();
    return _booting ??= _start();
  }

  static Future<void> _start() async {
    final rx = ReceivePort();
    final ready = Completer<SendPort>();
    rx.listen((Object? msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      if (msg is! Map) return;
      final done = _pending.remove(msg['id'] as int);
      if (done == null || done.isCompleted) return;
      if (msg['ok'] == true) {
        done.complete();
      } else {
        done.completeError(
          PageDownloadException(msg['error'] as String? ?? 'download failed'),
        );
      }
    });
    _isolate = await Isolate.spawn(_entry, rx.sendPort, debugName: 'pages');
    _rx = rx;
    _tx = await ready.future;
  }

  /// Test seam.
  static void shutdownForTest() {
    _isolate?.kill(priority: Isolate.immediate);
    _rx?.close();
    _isolate = null;
    _tx = null;
    _rx = null;
    _booting = null;
    _pending.clear();
  }
}

class PageDownloadException implements Exception {
  PageDownloadException(this.message);

  final String message;

  @override
  String toString() => 'PageDownloadException: $message';
}

/// Everything below this line runs on the download isolate.

/// Byte ceiling for the page store. Mihon's `ChapterCache` defaults to 100MiB;
/// long-strip pages are fatter than the paged manga that number was chosen for,
/// so this is roomier. Pruned oldest-first, on this isolate, never on the UI
/// thread.
const int _storeCapBytes = 256 * 1024 * 1024;

/// Prune is a full directory walk, so it does not run on every page.
const int _pruneEvery = 25;

Future<void> _entry(SendPort boot) async {
  final rx = ReceivePort();
  boot.send(rx.sendPort);

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15)
    ..autoUncompress = true;

  var sincePrune = 0;

  await for (final Object? msg in rx) {
    if (msg is! Map) continue;
    final id = msg['id'] as int;
    final reply = boot;
    try {
      final dest = msg['dest'] as String;
      final request = await client.getUrl(Uri.parse(msg['url'] as String));
      final headers = (msg['headers'] as Map?)?.cast<String, String>();
      headers?.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Drain so the connection can be reused rather than torn down.
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}');
      }
      // Write to a sibling `.part` and rename, so a fetch killed midway can
      // never leave a truncated file that later reads as a valid cache hit.
      final part = File('$dest.part');
      await response.pipe(part.openWrite());
      await part.rename(dest);

      if (++sincePrune >= _pruneEvery) {
        sincePrune = 0;
        await _prune(File(dest).parent);
      }
      reply.send(<String, Object?>{'id': id, 'ok': true});
    } catch (e) {
      reply.send(<String, Object?>{'id': id, 'ok': false, 'error': '$e'});
    }
  }
}

/// Drops the oldest files until the store is back under [_storeCapBytes].
Future<void> _prune(Directory dir) async {
  try {
    final files = <File>[];
    var total = 0;
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File) continue;
      files.add(entry);
      total += await entry.length();
    }
    if (total <= _storeCapBytes) return;
    final stamped = <MapEntry<File, DateTime>>[];
    for (final f in files) {
      stamped.add(MapEntry(f, (await f.stat()).modified));
    }
    stamped.sort((a, b) => a.value.compareTo(b.value));
    for (final entry in stamped) {
      if (total <= _storeCapBytes) return;
      total -= await entry.key.length();
      await entry.key.delete();
    }
  } catch (_) {
    // A cache that cannot be pruned is a disk-space problem, not a correctness
    // one — never let it fail a page load.
  }
}
