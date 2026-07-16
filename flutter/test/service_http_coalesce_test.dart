import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/source/js/js_runtime.dart';

/// Counts every request that actually reaches the adapter and holds each
/// response until [release] is called, so the test can guarantee requests
/// overlap in flight.
class _CountingAdapter implements HttpClientAdapter {
  int hits = 0;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hits++;
    await _gate.future;
    return ResponseBody.fromString('body-of ${options.uri}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('concurrent identical GETs share one network fetch', () async {
    final adapter = _CountingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final runtime = JsRuntime(dio: dio);

    final a = runtime.serviceHttp(
      '{"method":"GET","url":"https://coalesce.test/same"}',
    );
    final b = runtime.serviceHttp(
      '{"method":"GET","url":"https://coalesce.test/same"}',
    );
    // Both callers are now either awaiting the shared future or the gate.
    await Future<void>.delayed(Duration.zero);
    adapter.release();
    final results = await Future.wait([a, b]);

    expect(adapter.hits, 1);
    expect(results[0]['ok'], true);
    expect(results[1]['ok'], true);
    expect(results[0]['body'], results[1]['body']);
  });

  test('different URLs do not coalesce', () async {
    final adapter = _CountingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final runtime = JsRuntime(dio: dio);

    final a = runtime.serviceHttp(
      '{"method":"GET","url":"https://coalesce.test/one"}',
    );
    final b = runtime.serviceHttp(
      '{"method":"GET","url":"https://coalesce.test/two"}',
    );
    await Future<void>.delayed(Duration.zero);
    adapter.release();
    await Future.wait([a, b]);

    expect(adapter.hits, 2);
  });
}
