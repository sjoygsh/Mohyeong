// ===========================================================================
// Source icons — the real logo off the source's own website.
//
// A browse list of thirty sources led by thirty identical glyphs is a list you
// have to read line by line. Every one of these sources IS a website, and every
// website already publishes its own mark, so that is what the row wears.
//
// The mark is resolved once per source, ever: the site's own `<head>` is read
// for the icons it declares, the candidates are tried in quality order, and
// the winner is decoded and written into the app's support directory. From
// then on the row paints from a local file — no network on scroll, nothing to
// re-probe on launch.
//
// Nothing here talks to a third-party favicon service. The request goes to the
// site the user is already browsing, with that source's own headers, or it
// doesn't happen.
// ===========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../network/app_http_client.dart';
import '../network/network_preferences.dart';

/// What [SourceIconStore.resolve] needs to go and look, as one value so it can
/// key a provider family.
typedef SourceIconRequest = ({String id, String baseUrl, String? userAgent});

/// Whether a probe ever got an answer out of the host, of any kind.
///
/// "The site serves no icon we can use" and "the phone was on a train" both
/// end in no image, but they are not the same fact and they must not be
/// remembered for the same length of time.
class _Reach {
  bool answered = false;
}

/// One remembered probe.
class _IconRecord {
  const _IconRecord({
    required this.base,
    required this.attemptedAt,
    this.file,
    this.url,
    this.answered = true,
    this.decoder = 0,
  });

  /// The `base_url` the probe was made against. A source that moves domain
  /// re-probes rather than keeping the old site's mark.
  final String base;
  final DateTime attemptedAt;

  /// Basename of the stored image inside the icon directory. Null on a miss.
  final String? file;

  /// The URL the mark actually came from — kept for debugging and so a
  /// re-probe can tell "same answer" from "moved".
  final String? url;

  /// Whether the host responded at all. A miss where it did is a real answer
  /// about the site; a miss where it didn't is a fact about the network.
  final bool answered;

  /// Which decoder generation recorded this. A miss written by an older one
  /// says nothing about what the current one can read — see
  /// [SourceIconStore._decoderGeneration].
  final int decoder;

  bool get found => file != null;

  Map<String, dynamic> toJson() => {
        'base': base,
        'at': attemptedAt.millisecondsSinceEpoch,
        if (file != null) 'file': file,
        if (url != null) 'url': url,
        if (!answered) 'unreachable': true,
        'decoder': decoder,
      };

  static _IconRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final base = json['base'];
    final at = json['at'];
    if (base is! String || at is! int) return null;
    return _IconRecord(
      base: base,
      attemptedAt: DateTime.fromMillisecondsSinceEpoch(at),
      file: json['file'] as String?,
      url: json['url'] as String?,
      answered: json['unreachable'] != true,
      decoder: json['decoder'] as int? ?? 0,
    );
  }
}

/// Resolves and caches one image per source. Single instance — the in-flight
/// map is what stops a screenful of rows all probing the same site at once.
class SourceIconStore {
  SourceIconStore._();

  static final SourceIconStore instance = SourceIconStore._();

  /// A site that answered, and had no usable mark, is not asked again for this
  /// long. Half a day rather than the week it first looked like it deserved:
  /// probing a first run of 25 sources twice showed the SAME site resolving
  /// once and failing once, so "the host answered and had nothing" is not the
  /// settled fact it sounds like — a CDN hiccup on the icon itself lands here
  /// too. One cheap request per source per half-day, only when Browse is
  /// opened, buys back a mark that would otherwise stay a letter for a week.
  static const _retryAfterMiss = Duration(hours: 12);

  /// A host that never answered at all gets asked again sooner still. The
  /// first run of Browse probes every source at once, which is exactly when a
  /// phone is most likely to drop one.
  static const _retryAfterUnreachable = Duration(hours: 1);

  /// Which generation of [sniffImage] is in the build. A remembered MISS is
  /// only a fact about what the decoder of the day could read: WEBTOONS
  /// publishes a single 32x32 32bpp BMP inside its .ico, which generation 1
  /// could not decode and generation 2 can — and yet the row kept its letter,
  /// because the miss recorded before the fix shipped was still inside its
  /// 12-hour TTL and nothing about an app update could shorten it. Misses from
  /// an older generation are re-probed at once. Bump this whenever
  /// [sniffImage] learns a format.
  ///
  ///   1 — PNG / JPEG / GIF / WebP / BMP, and PNG-inside-.ico
  ///   2 — plus BMP-inside-.ico (32bpp and 24bpp, BI_RGB)
  static const _decoderGeneration = 2;

  /// Anything bigger than this is not a favicon and we are not decoding it.
  static const _maxBytes = 512 * 1024;

  /// Hops allowed while chasing the page that actually declares the icons.
  /// Enough for apex → www → locale; short enough that a redirect loop ends.
  static const _maxRedirects = 4;

  /// Probes allowed to be in the air at once. A first run of Browse with
  /// thirty sources installed would otherwise open thirty simultaneous
  /// connections to thirty different hosts the moment the list builds — on a
  /// phone that competes with the covers the user is actually waiting for.
  static const _maxConcurrentProbes = 4;

  Directory? _dir;
  Map<String, _IconRecord>? _index;
  Future<void>? _loading;

  /// Resolutions in flight, so twenty rows of the same source share one probe.
  final Map<String, Future<String?>> _pending = {};

  int _probing = 0;
  final List<Completer<void>> _waiting = [];

  /// Absolute path of the stored mark for [request], or null when the site
  /// publishes nothing we can decode.
  Future<String?> resolve(SourceIconRequest request) {
    final base = request.baseUrl.trim();
    if (base.isEmpty) return Future<String?>.value(null);
    final existing = _pending[request.id];
    if (existing != null) return existing;
    final future = _resolve(request, base);
    _pending[request.id] = future;
    // Cleared either way: a miss that later becomes a hit (site adds an icon,
    // extension changes domain) has to be reachable without an app restart.
    // `ignore` because this derived future has no listener — without it a
    // failure here would surface as an unhandled async error.
    future.whenComplete(() => _pending.remove(request.id)).ignore();
    return future;
  }

  Future<String?> _resolve(SourceIconRequest request, String base) async {
    // A logo is decoration. Nothing about failing to store one — no support
    // directory, a read-only filesystem — may propagate out of here as an
    // error the UI has to think about; the row just keeps its sigil.
    try {
      return await _resolveOrThrow(request, base);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveOrThrow(SourceIconRequest request, String base) async {
    final dir = await _directory();
    final index = await _readIndex();
    final record = index[request.id];

    if (record != null && record.base == base) {
      if (record.found) {
        final file = File(p.join(dir.path, record.file!));
        if (file.existsSync()) return file.path;
        // The file was cleared out from under us — fall through and re-probe.
      } else if (record.decoder >= _decoderGeneration &&
          DateTime.now().difference(record.attemptedAt) <
              (record.answered ? _retryAfterMiss : _retryAfterUnreachable)) {
        return null;
      }
    }

    String? storedName;
    String? sourceUrl;
    final reach = _Reach();
    await _acquire();
    try {
      final found = await _probe(base, request.userAgent, reach);
      if (found != null) {
        storedName = '${_safeName(request.id)}.${found.extension}';
        await File(p.join(dir.path, storedName)).writeAsBytes(found.bytes);
        sourceUrl = found.url;
      }
    } catch (_) {
      // Offline, blocked, timed out — recorded as a miss and retried later.
    } finally {
      _release();
    }

    await _writeRecord(
      request.id,
      _IconRecord(
        base: base,
        attemptedAt: DateTime.now(),
        file: storedName,
        url: sourceUrl,
        answered: reach.answered,
        decoder: _decoderGeneration,
      ),
    );
    return storedName == null ? null : p.join(dir.path, storedName);
  }

  /// Drops everything remembered about [id] so the next lookup probes fresh.
  Future<void> forget(String id) async {
    final dir = await _directory();
    final index = await _readIndex();
    final record = index.remove(id);
    if (record?.file != null) {
      final file = File(p.join(dir.path, record!.file!));
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Best effort — a stale image is harmless, it just gets overwritten.
        }
      }
    }
    await _flush(index);
  }

  // -------------------------------------------------------------------------
  // Probing
  // -------------------------------------------------------------------------

  Future<void> _acquire() {
    if (_probing < _maxConcurrentProbes) {
      _probing++;
      return Future<void>.value();
    }
    final slot = Completer<void>();
    _waiting.add(slot);
    return slot.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // The permit passes straight to the next waiter — _probing stays at the
      // cap rather than dipping and being re-taken.
      _waiting.removeAt(0).complete();
      return;
    }
    _probing--;
  }

  Future<({Uint8List bytes, String extension, String url})?> _probe(
    String base,
    String? userAgent,
    _Reach reach,
  ) async {
    final origin = Uri.tryParse(base);
    if (origin == null || !origin.hasScheme) return null;
    final client = await AppHttpClient.instance();
    final headers = <String, String>{
      'User-Agent': userAgent ?? defaultUserAgent,
      'Referer': '${base.replaceAll(RegExp(r'/+$'), '')}/',
    };

    final candidates = <Uri>[
      ...await _declaredIcons(client.dio, origin, headers, reach),
      // The conventional paths, tried after whatever the page declared: a
      // site that names its icon means it, and these are the guesses.
      origin.resolve('/apple-touch-icon.png'),
      origin.resolve('/apple-touch-icon-precomposed.png'),
      origin.resolve('/favicon.png'),
      origin.resolve('/favicon.ico'),
    ];

    final seen = <String>{};
    for (final candidate in candidates) {
      final key = candidate.toString();
      if (!seen.add(key)) continue;
      final image = await _fetchImage(client.dio, candidate, headers, reach);
      if (image != null) {
        return (bytes: image.bytes, extension: image.extension, url: key);
      }
    }
    return null;
  }

  /// The icons the page's own `<head>` declares, best first.
  ///
  /// Parsed with a regex rather than a DOM: the app has no HTML parser, and
  /// pulling one in to read four attributes out of a `<link>` would be the
  /// larger change. A malformed match costs one failed fetch.
  ///
  /// Redirects are followed by hand. A manga site's apex very often bounces —
  /// to a locale path, a mobile host, or a whole new domain — and a 3xx body
  /// is empty, so a redirect read as a page looks exactly like a site that
  /// declares no icons at all. Following it also means relative hrefs resolve
  /// against the page that actually declared them rather than against the
  /// address we started from.
  Future<List<Uri>> _declaredIcons(
    Dio dio,
    Uri origin,
    Map<String, String> headers,
    _Reach reach,
  ) async {
    var url = origin;
    for (var hop = 0; hop < _maxRedirects; hop++) {
      try {
        final response = await dio.getUri<String>(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            // Left on: when the HTTP client handles the redirect itself this
            // loop simply never sees a 3xx. The manual hop is for the cases
            // where it hands one back.
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 12),
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        reach.answered = true;
        final status = response.statusCode ?? 0;
        if (status >= 300) {
          final location = response.headers.value('location');
          if (location == null || location.isEmpty) return const [];
          final next = _absolute(url, location);
          if (next == null || next == url) return const [];
          url = next;
          continue;
        }
        return iconLinksIn(response.data ?? '', url);
      } on DioException catch (e) {
        // A wall is not an answer — see [isAnswerStatus]. A 404 on the apex is.
        if (isAnswerStatus(e.response?.statusCode)) reach.answered = true;
        // The conventional paths are often served by the edge even when the
        // page itself is walled, so a failure here is not the end of the probe.
        return const [];
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  /// The icon URLs declared by [html], best first. Pure — [_declaredIcons]
  /// fetches, this decides.
  @visibleForTesting
  static List<Uri> iconLinksIn(String html, Uri origin) {
    if (html.isEmpty) return const [];
    // Icons live in <head>; scanning a whole chapter-list page body for link
    // tags is wasted work on a document that can be megabytes.
    final headEnd = html.indexOf('</head>');
    final head = headEnd == -1
        ? (html.length > 200000 ? html.substring(0, 200000) : html)
        : html.substring(0, headEnd);

    final found = <({Uri uri, int rank, int area})>[];
    for (final match in RegExp(
      r'<link\s[^>]*>',
      caseSensitive: false,
    ).allMatches(head)) {
      final tag = match.group(0)!;
      final rel = _attribute(tag, 'rel')?.toLowerCase();
      if (rel == null || !rel.contains('icon')) continue;
      final href = _attribute(tag, 'href');
      if (href == null || href.isEmpty) continue;
      final uri = _absolute(origin, href);
      if (uri == null) continue;
      // Nothing in the app decodes SVG, and a data: URI is not worth a second
      // decoder path for the handful of sites that inline one.
      final path = uri.path.toLowerCase();
      if (path.endsWith('.svg') || uri.scheme == 'data') continue;
      // An apple-touch-icon is a real logo at a real size; a plain "icon" is
      // often a 16px glyph that turns to mush at 38dp.
      final rank = rel.contains('apple-touch-icon') ? 2 : 1;
      found.add((uri: uri, rank: rank, area: _sizeArea(_attribute(tag, 'sizes'))));
    }
    found.sort((a, b) {
      final byRank = b.rank.compareTo(a.rank);
      if (byRank != 0) return byRank;
      final byArea = b.area.compareTo(a.area);
      // Same rank and same (or absent) size is the common case — a page
      // listing several unsized `icon` links — and Dart's sort is not stable,
      // so the winner would otherwise vary run to run for one page.
      return byArea != 0 ? byArea : a.uri.toString().compareTo(b.uri.toString());
    });
    return [for (final f in found) f.uri];
  }

  /// Fetches [uri] and returns its bytes when they decode as something the
  /// engine can paint.
  Future<({Uint8List bytes, String extension})?> _fetchImage(
    Dio dio,
    Uri uri,
    Map<String, String> headers,
    _Reach reach,
  ) async {
    try {
      final response = await dio.getUri<List<int>>(
        uri,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 12),
          validateStatus: (status) => status == 200,
        ),
      );
      reach.answered = true;
      final data = response.data;
      if (data == null || data.isEmpty || data.length > _maxBytes) return null;
      // Content-Type is not trusted on its own: plenty of these hosts answer a
      // missing /favicon.ico with a 200 and an HTML error page.
      return sniffImage(Uint8List.fromList(data));
    } on DioException catch (e) {
      // A 404 for /favicon.ico is the host telling us it has none — that is an
      // answer, and it is why an unreachable host must be tracked separately.
      if (isAnswerStatus(e.response?.statusCode)) reach.answered = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether [status] is the HOST telling us something about its icon, rather
  /// than an edge refusing to let us ask.
  ///
  /// A 404 is an answer: there is no icon there. A Cloudflare 403 or 503 is
  /// not — it is the same wall the extensions themselves only get past on the
  /// device's WebView, and it says nothing at all about whether the site has a
  /// mark. Counting it as an answer parked those sources on the 12-hour
  /// "asked and it had nothing" TTL, so brainrotcomics, manhuaus and manhwatop
  /// kept their letter tiles for half a day at a time off a wall we already
  /// know how to get through. They now take the 1-hour unreachable TTL.
  @visibleForTesting
  static bool isAnswerStatus(int? status) {
    if (status == null) return false;
    return status != 403 && status != 429 && status != 503;
  }

  /// Identifies [bytes] by their magic number, and unwraps the one container
  /// format the engine cannot read. Null when this is not an image the engine
  /// can paint — which is how an HTML error page served under a 200 at
  /// `/favicon.ico` gets rejected.
  @visibleForTesting
  static ({Uint8List bytes, String extension})? sniffImage(Uint8List bytes) {
    if (bytes.length < 12) return null;
    bool starts(List<int> magic) {
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return (bytes: bytes, extension: 'png');
    if (starts(const [0xFF, 0xD8, 0xFF])) return (bytes: bytes, extension: 'jpg');
    if (starts(const [0x47, 0x49, 0x46, 0x38])) return (bytes: bytes, extension: 'gif');
    if (starts(const [0x42, 0x4D])) return (bytes: bytes, extension: 'bmp');
    if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return (bytes: bytes, extension: 'webp');
    }
    if (starts(const [0x00, 0x00, 0x01, 0x00])) return _unwrapIco(bytes);
    return null;
  }

  /// Pulls a paintable image out of an `.ico`.
  ///
  /// Skia has no ICO decoder, so a raw .ico is unpaintable. A modern
  /// favicon.ico is usually a container holding PNGs, and the largest of those
  /// is exactly the image we want — that is a slice, and it is tried first.
  ///
  /// Failing that, the entry is the older BMP-with-mask form, which is a real
  /// decode rather than a slice: the DIB's height is DOUBLED to cover an AND
  /// mask that follows the colour data, so the bytes cannot be handed to Skia
  /// as a `.bmp` either. [_bmpIconToPng] does that decode. It is worth the
  /// forty lines because it is not an exotic case — tapas.io, a working
  /// source, ships exactly one 32bpp BMP entry and had no logo because of it.
  static ({Uint8List bytes, String extension})? _unwrapIco(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final count = data.getUint16(4, Endian.little);
    if (count == 0) return null;
    var bestOffset = -1;
    var bestLength = 0;
    for (var i = 0; i < count; i++) {
      final entry = 6 + i * 16;
      if (entry + 16 > bytes.length) break;
      final length = data.getUint32(entry + 8, Endian.little);
      final offset = data.getUint32(entry + 12, Endian.little);
      if (offset + length > bytes.length || length < 8) continue;
      // PNG magic at the entry's own offset — a BMP entry starts with its
      // BITMAPINFOHEADER size instead and is skipped.
      if (bytes[offset] != 0x89 ||
          bytes[offset + 1] != 0x50 ||
          bytes[offset + 2] != 0x4E ||
          bytes[offset + 3] != 0x47) {
        continue;
      }
      if (length > bestLength) {
        bestLength = length;
        bestOffset = offset;
      }
    }
    if (bestOffset >= 0) {
      return (
        bytes: Uint8List.sublistView(bytes, bestOffset, bestOffset + bestLength),
        extension: 'png',
      );
    }
    return _bmpIconToPng(bytes, data, count);
  }

  /// Decodes the largest uncompressed BMP entry of an `.ico` into a PNG.
  ///
  /// Handles the two bit depths favicons actually use, 32bpp BGRA and 24bpp
  /// BGR. Anything palletised, RLE-compressed or otherwise exotic returns null
  /// rather than guessing — a wrong logo is worse than the letter tile.
  static ({Uint8List bytes, String extension})? _bmpIconToPng(
    Uint8List bytes,
    ByteData data,
    int count,
  ) {
    var bestEntry = -1;
    var bestPixels = 0;
    for (var i = 0; i < count; i++) {
      final entry = 6 + i * 16;
      if (entry + 16 > bytes.length) break;
      final length = data.getUint32(entry + 8, Endian.little);
      final offset = data.getUint32(entry + 12, Endian.little);
      if (offset + length > bytes.length || length < 40) continue;
      // A BITMAPINFOHEADER announces itself with its own size.
      if (data.getUint32(offset, Endian.little) != 40) continue;
      final w = data.getInt32(offset + 4, Endian.little);
      if (w <= 0 || w > _maxIconEdge) continue;
      if (w * w > bestPixels) {
        bestPixels = w * w;
        bestEntry = offset;
      }
    }
    if (bestEntry < 0) return null;

    final width = data.getInt32(bestEntry + 4, Endian.little);
    // Doubled to cover the AND mask stored after the colour data.
    final height = data.getInt32(bestEntry + 8, Endian.little) ~/ 2;
    final bits = data.getUint16(bestEntry + 14, Endian.little);
    final compression = data.getUint32(bestEntry + 16, Endian.little);
    if (height <= 0 || compression != 0) return null;
    if (bits != 32 && bits != 24) return null;

    final bytesPerPixel = bits ~/ 8;
    // DIB rows are padded to a 4-byte boundary.
    final stride = ((width * bytesPerPixel + 3) ~/ 4) * 4;
    final pixels = bestEntry + 40;
    if (pixels + stride * height > bytes.length) return null;

    // One filter byte per row, then RGBA. Rows are bottom-up in a DIB.
    final raw = Uint8List(height * (1 + width * 4));
    var out = 0;
    for (var y = 0; y < height; y++) {
      raw[out++] = 0; // filter: none
      final row = pixels + (height - 1 - y) * stride;
      for (var x = 0; x < width; x++) {
        final px = row + x * bytesPerPixel;
        raw[out++] = bytes[px + 2]; // B,G,R stored little-endian
        raw[out++] = bytes[px + 1];
        raw[out++] = bytes[px];
        raw[out++] = bytesPerPixel == 4 ? bytes[px + 3] : 0xFF;
      }
    }
    return (bytes: _encodePng(width, height, raw), extension: 'png');
  }

  /// The smallest PNG that can carry 8-bit RGBA: signature, IHDR, one IDAT of
  /// zlib-compressed scanlines, IEND. Written by hand because the app has no
  /// image encoder and pulling one in for a favicon would be the larger cost.
  static Uint8List _encodePng(int width, int height, Uint8List raw) {
    final out = BytesBuilder();
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void chunk(String type, List<int> body) {
      final header = ByteData(4)..setUint32(0, body.length);
      out.add(header.buffer.asUint8List());
      final typed = <int>[...type.codeUnits, ...body];
      out.add(typed);
      final crc = ByteData(4)..setUint32(0, getCrc32(typed));
      out.add(crc.buffer.asUint8List());
    }

    final ihdr = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // colour type: RGBA
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    chunk('IHDR', ihdr.buffer.asUint8List());
    chunk('IDAT', zlib.encode(raw));
    chunk('IEND', const []);
    return out.toBytes();
  }

  static String? _attribute(String tag, String name) {
    final quoted = RegExp(
      '$name\\s*=\\s*"([^"]*)"|$name\\s*=\\s*\'([^\']*)\'',
      caseSensitive: false,
    ).firstMatch(tag);
    if (quoted != null) return quoted.group(1) ?? quoted.group(2);
    final bare =
        RegExp('$name\\s*=\\s*([^\\s>]+)', caseSensitive: false).firstMatch(tag);
    return bare?.group(1);
  }

  /// Largest edge a `sizes` attribute can claim and still be describing an
  /// icon. Past this it is junk, and treating it as junk is what keeps the
  /// multiply below in range.
  static const int _maxIconEdge = 8192;

  /// `sizes="180x180"` → 32400. Unsized (or `any`) sorts last among peers.
  static int _sizeArea(String? sizes) {
    if (sizes == null) return 0;
    var best = 0;
    for (final match in RegExp(r'(\d+)\s*[xX]\s*(\d+)').allMatches(sizes)) {
      // `\d+` is unbounded and this string comes straight out of a stranger's
      // markup. `int.parse` THROWS on a digit run past what fits in 64 bits,
      // and a value that does parse can still overflow the multiply and come
      // back NEGATIVE — which would sort a huge icon last instead of first.
      // Anything past a plausible icon edge is not a size, so it is skipped.
      final w = int.tryParse(match.group(1)!);
      final h = int.tryParse(match.group(2)!);
      if (w == null || h == null) continue;
      if (w <= 0 || h <= 0 || w > _maxIconEdge || h > _maxIconEdge) continue;
      final area = w * h;
      if (area > best) best = area;
    }
    return best;
  }

  static Uri? _absolute(Uri origin, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;
    try {
      // Protocol-relative (`//cdn.example/icon.png`) resolves against the
      // page's own scheme, which Uri.resolve already does correctly.
      return origin.resolve(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// Extension ids come from a manifest and end up as a filename.
  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // -------------------------------------------------------------------------
  // Index
  // -------------------------------------------------------------------------

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'source_icons'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  File _indexFile(Directory dir) => File(p.join(dir.path, 'index.json'));

  Future<Map<String, _IconRecord>> _readIndex() async {
    final loaded = _index;
    if (loaded != null) return loaded;
    // Two rows arriving together must not both parse (and then both write) the
    // index — the second would clobber the first's record. Cleared when it
    // settles: a load that failed (no support directory yet) must not stay
    // memoised, or every later lookup awaits the same dead future and the
    // whole feature is off until the app restarts. Clearing on success is
    // harmless — [_index] is set by then, so the early return above wins.
    await (_loading ??= _load().whenComplete(() => _loading = null));
    return _index!;
  }

  Future<void> _load() async {
    final dir = await _directory();
    final map = <String, _IconRecord>{};
    final file = _indexFile(dir);
    if (file.existsSync()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          for (final entry in json.entries) {
            final record = _IconRecord.fromJson(entry.value);
            if (record != null) map[entry.key as String] = record;
          }
        }
      } catch (_) {
        // Corrupt index — start over rather than lose the whole feature.
      }
    }
    _index = map;
  }

  Future<void> _writeRecord(String id, _IconRecord record) async {
    final index = await _readIndex();
    index[id] = record;
    await _flush(index);
  }

  Future<void> _flush(Map<String, _IconRecord> index) async {
    final dir = await _directory();
    try {
      await _indexFile(dir).writeAsString(
        jsonEncode({for (final e in index.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {
      // The images are still on disk; a lost index costs one re-probe.
    }
  }
}

/// Path to a source's own logo, or null while it resolves and when the site
/// publishes nothing usable. Not auto-disposed: a resolved path is a few bytes
/// and scrolling a source list must not re-run the lookup.
final sourceIconProvider =
    FutureProvider.family<String?, SourceIconRequest>((ref, request) {
  return SourceIconStore.instance.resolve(request);
});
