import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_http_client.dart';

/// The image cache's downloader, on the app's ONE HTTP client.
///
/// `flutter_cache_manager` ships with an `HttpFileService` built on a bare
/// `http.Client`: no cookie jar, no User-Agent, none of the app's timeouts. So
/// every cover and every reader page went to the origin as an anonymous
/// request while the extension that produced the URL fetched its HTML through
/// [AppHttpClient] — same host, same session, different client. On a
/// Cloudflare-fronted source the HTML request carries the `cf_clearance` the
/// solver WebView minted and succeeds; the image request carries nothing and
/// comes back 403.
///
/// That 403 was not a broken image on screen, because [SourceImage] catches it
/// and re-fetches through the offscreen WebView — so the pages did arrive, and
/// the only visible symptom was that the reader stuttered. Measured: every
/// page of a chapter taking that path, and Chromium's renderer, GPU process
/// and Android's RenderThread between them burning several CPU-seconds per ten
/// seconds of scrolling on a phone that has none to spare. Flutter's UI thread
/// then could not get scheduled: frames cost 0.3ms to build and 2.5ms to
/// raster and still started 20ms late, which is 20fps of visible judder with
/// no expensive frame anywhere in the trace.
///
/// Mihon has never had this problem because Coil loads images through the same
/// OkHttp client as the source, cookie jar and all. This is that, and the
/// WebView fallback goes back to being what it is meant to be: the last resort
/// for a host that genuinely will not serve a non-browser client.
class SourceFileService extends FileService {
  SourceFileService({FileService? fallback})
      : _fallback = fallback ?? HttpFileService();

  /// Used when the shared client can't be built — most plausibly in the
  /// WorkManager background isolate, whose plugin registrations come up
  /// independently. An anonymous download is worth more than none.
  final FileService _fallback;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final Dio dio;
    try {
      dio = (await AppHttpClient.instance()).dio;
    } catch (_) {
      return _fallback.get(url, headers: headers);
    }
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        // The cache manager decides what counts as a failure (it throws its
        // own HttpExceptionWithStatus); Dio must not throw first, or a 404
        // arrives as a DioException instead of a status the caller can read.
        validateStatus: (_) => true,
      ),
    );
    final status = response.statusCode ?? 500;
    if (status != HttpStatus.ok && status != HttpStatus.created) {
      // The cache manager throws on a bad status without ever listening to the
      // body, and an unread streamed response holds its connection until the
      // socket times out. On a source that 403s every page that is one stuck
      // connection per page.
      unawaited(response.data?.stream.drain<void>().catchError((_) {}) ??
          Future<void>.value());
    }
    return DioFileServiceResponse(response);
  }
}

/// [FileServiceResponse] over a Dio streamed response. Visible for testing:
/// the cache-control and content-type rules below decide how long a cover
/// stays cached and what a page file is called on disk.
class DioFileServiceResponse implements FileServiceResponse {
  DioFileServiceResponse(this._response);

  final Response<ResponseBody> _response;
  final DateTime _received = DateTime.now();

  String? _header(String name) => _response.headers.value(name);

  @override
  Stream<List<int>> get content =>
      _response.data?.stream ?? const Stream<List<int>>.empty();

  @override
  int? get contentLength {
    final raw = _header(HttpHeaders.contentLengthHeader);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  int get statusCode => _response.statusCode ?? 500;

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  /// Same rule as the package's own `HttpGetResponse`: honour `max-age` and
  /// `no-cache`, keep for a week otherwise.
  @override
  DateTime get validTill {
    var age = const Duration(days: 7);
    final control = _header(HttpHeaders.cacheControlHeader);
    if (control != null) {
      for (final setting in control.split(',')) {
        final s = setting.trim().toLowerCase();
        if (s == 'no-cache') age = Duration.zero;
        if (s.startsWith('max-age=')) {
          final seconds = int.tryParse(s.split('=')[1]) ?? 0;
          if (seconds > 0) age = Duration(seconds: seconds);
        }
      }
    }
    return _received.add(age);
  }

  @override
  String get fileExtension {
    final raw = _header(HttpHeaders.contentTypeHeader);
    if (raw == null) return '';
    final ContentType type;
    try {
      type = ContentType.parse(raw);
    } catch (_) {
      return '';
    }
    final known = _extensions[type.mimeType];
    if (known != null) return known;
    // A blank or typeless header parses without throwing; a bare "." is not a
    // file extension, and the cache manager would name the file with it.
    return type.subType.isEmpty ? '' : '.${type.subType}';
  }

  /// The image types a source actually serves. The package keeps a full MIME
  /// table in `src/`, which is not exported; anything missed falls back to the
  /// subtype, exactly as it does.
  static const Map<String, String> _extensions = <String, String>{
    'image/jpeg': '.jpg',
    'image/jpg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/avif': '.avif',
    'image/bmp': '.bmp',
    'image/svg+xml': '.svg',
  };
}
