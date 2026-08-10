import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/network/image_file_service.dart';

/// The image cache used to download through the package's anonymous
/// `HttpFileService`, so a page request never carried the session its own
/// source had established — a Cloudflare-fronted host answered 403 and every
/// page fell through to the offscreen WebView, which is what made the reader
/// stutter. [SourceFileService] puts those downloads on the app's one client;
/// this pins the response contract the cache manager reads back, which decides
/// what it caches and for how long.
void main() {
  DioFileServiceResponse response({
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    return DioFileServiceResponse(
      Response<ResponseBody>(
        requestOptions: RequestOptions(path: 'https://example.com/1.webp'),
        statusCode: status,
        headers: Headers.fromMap(headers),
        data: ResponseBody(
          const Stream<Uint8List>.empty(),
          status,
          headers: headers,
        ),
      ),
    );
  }

  test('a rejected page reports its status instead of throwing', () {
    // The cache manager raises its own HttpExceptionWithStatus off this; if
    // Dio threw first the caller would see a DioException with no status, and
    // SourceImage could not tell a 403 apart from a dead network.
    expect(response(status: 403).statusCode, 403);
  });

  test('content type decides the file extension', () {
    expect(
      response(headers: {
        'content-type': ['image/webp']
      }).fileExtension,
      '.webp',
    );
    expect(
      response(headers: {
        'content-type': ['image/jpeg']
      }).fileExtension,
      '.jpg',
    );
  });

  test('an unlisted image type falls back to its subtype', () {
    expect(
      response(headers: {
        'content-type': ['image/heic']
      }).fileExtension,
      '.heic',
    );
  });

  test('a missing or unparseable content type yields no extension', () {
    expect(response().fileExtension, '');
    expect(
      response(headers: {
        'content-type': ['']
      }).fileExtension,
      '',
    );
  });

  test('max-age sets how long the entry stays valid', () {
    final r = response(headers: {
      'cache-control': ['public, max-age=600']
    });
    final held = r.validTill.difference(DateTime.now());
    expect(held.inSeconds, closeTo(600, 5));
  });

  test('no-cache means do not hold it at all', () {
    final r = response(headers: {
      'cache-control': ['no-cache']
    });
    expect(r.validTill.isAfter(DateTime.now().add(const Duration(seconds: 2))),
        isFalse);
  });

  test('without cache-control an image is kept for a week', () {
    final held = response().validTill.difference(DateTime.now());
    expect(held.inHours, closeTo(24 * 7, 1));
  });

  test('content length is read when the origin sends it', () {
    expect(
      response(headers: {
        'content-length': ['4096']
      }).contentLength,
      4096,
    );
    expect(response().contentLength, isNull);
  });

  test('the etag rides along for revalidation', () {
    expect(
      response(headers: {
        'etag': ['"abc123"']
      }).eTag,
      '"abc123"',
    );
  });
}
