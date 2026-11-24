import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/common/source_image.dart';

/// The offscreen WebView fallback runs on the main thread Flutter's frames
/// run on. It is worth that only where a browser can succeed and the plain
/// download could not: a fingerprint wall. A missing image or a dead host
/// fails in the browser too, and sending one there stalled the library scroll
/// once per dead cover per pass.
void main() {
  HttpExceptionWithStatus status(int code) =>
      HttpExceptionWithStatus(code, 'Invalid statusCode: $code');

  test('a wall is worth the WebView', () {
    for (final code in [401, 403, 429, 503]) {
      expect(browserCouldFetchImage(status(code)), isTrue, reason: '$code');
    }
  });

  test('a missing image or an unreachable origin is not', () {
    for (final code in [404, 410, 500, 522, 525]) {
      expect(browserCouldFetchImage(status(code)), isFalse, reason: '$code');
    }
  });

  test('a host that does not resolve is not', () {
    final e = DioException.connectionError(
      requestOptions: RequestOptions(path: 'https://n17.example/x.jpg'),
      reason: 'Failed host lookup',
      error: const SocketException("Failed host lookup: 'n17.example'"),
    );
    expect(browserCouldFetchImage(e), isFalse);
  });

  test('a Dio rejection is judged by its status', () {
    DioException rejected(int code) => DioException.badResponse(
          statusCode: code,
          requestOptions: RequestOptions(path: 'https://x.example/1.webp'),
          response: Response<void>(
            requestOptions: RequestOptions(path: 'https://x.example/1.webp'),
            statusCode: code,
          ),
        );
    expect(browserCouldFetchImage(rejected(403)), isTrue);
    expect(browserCouldFetchImage(rejected(404)), isFalse);
  });

  test('a reset before any answer still tries, since that is how a TLS '
      'fingerprint block looks', () {
    final e = DioException.connectionError(
      requestOptions: RequestOptions(path: 'https://cdn.example/1.webp'),
      reason: 'Connection reset by peer',
      error: const SocketException('Connection reset by peer'),
    );
    expect(browserCouldFetchImage(e), isTrue);
    expect(browserCouldFetchImage(Exception('unknown')), isTrue);
  });
}
