import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/network/call_timeout_adapter.dart';

/// Kotlin `NetworkHelper` caps a whole call at 2 minutes. Dio has no
/// equivalent: `connectTimeout` covers dialling, and `receiveTimeout` on a
/// streamed response measures the gap BETWEEN CHUNKS. A server that dribbles a
/// few bytes every twenty seconds satisfies both forever, and now that only one
/// chapter per source downloads at a time, one host stuck like that stalls that
/// source's queue with nothing to end it.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.headerDelay = Duration.zero, required this.body});

  final Duration headerDelay;
  final Stream<Uint8List> Function() body;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (headerDelay > Duration.zero) await Future<void>.delayed(headerDelay);
    return ResponseBody(body(), 200, headers: {});
  }

  @override
  void close({bool force = false}) => closed = true;
}

RequestOptions get _options => RequestOptions(path: '/page.jpg');

Uint8List _chunk() => Uint8List.fromList([1, 2, 3, 4]);

void main() {
  test('a body that arrives in time passes straight through', () async {
    final adapter = CallTimeoutAdapter(
      _FakeAdapter(body: () => Stream.fromIterable([_chunk(), _chunk()])),
      callTimeout: const Duration(seconds: 5),
    );

    final body = await adapter.fetch(_options, null, null);
    final bytes = await body.stream.expand((c) => c).toList();
    expect(bytes, [1, 2, 3, 4, 1, 2, 3, 4]);
  });

  test('a drip-fed body fails once the call budget runs out', () async {
    // The case Dio cannot catch: a chunk every 20ms, forever, well inside any
    // per-chunk receiveTimeout.
    final adapter = CallTimeoutAdapter(
      _FakeAdapter(
        body: () => Stream.periodic(
          const Duration(milliseconds: 20),
          (_) => _chunk(),
        ),
      ),
      callTimeout: const Duration(milliseconds: 200),
    );

    final body = await adapter.fetch(_options, null, null);
    await expectLater(
      body.stream.drain<void>(),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
  });

  test('headers that never arrive fail as a connection timeout', () async {
    final adapter = CallTimeoutAdapter(
      _FakeAdapter(
        headerDelay: const Duration(seconds: 5),
        body: () => const Stream<Uint8List>.empty(),
      ),
      callTimeout: const Duration(milliseconds: 100),
    );

    await expectLater(
      adapter.fetch(_options, null, null),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionTimeout,
        ),
      ),
    );
  });

  test('the body only gets what the headers left of the budget', () async {
    // Headers ate 150ms of a 250ms budget, so a body 200ms long must fail.
    final adapter = CallTimeoutAdapter(
      _FakeAdapter(
        headerDelay: const Duration(milliseconds: 150),
        body: () => Stream.periodic(
          const Duration(milliseconds: 20),
          (_) => _chunk(),
        ),
      ),
      callTimeout: const Duration(milliseconds: 250),
    );

    final started = DateTime.now();
    final body = await adapter.fetch(_options, null, null);
    await expectLater(body.stream.drain<void>(), throwsA(isA<DioException>()));
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(milliseconds: 900)),
      reason: 'the deadline is on the call, not restarted for the body',
    );
  });

  test('pause and resume reach the inner stream', () async {
    // A download pauses its stream while the disk sink catches up. Swallowing
    // that would buffer a whole page in memory.
    var paused = false;
    final controller = StreamController<Uint8List>(
      onPause: () => paused = true,
      onResume: () => paused = false,
    );
    final adapter = CallTimeoutAdapter(
      _FakeAdapter(body: () => controller.stream),
      callTimeout: const Duration(seconds: 5),
    );

    final body = await adapter.fetch(_options, null, null);
    final sub = body.stream.listen((_) {});
    await pumpEventQueue();

    sub.pause();
    await pumpEventQueue();
    expect(paused, isTrue);

    sub.resume();
    await pumpEventQueue();
    expect(paused, isFalse);

    await sub.cancel();
    await controller.close();
  });

  test('a real Dio still fetches through the wrapped adapter', () async {
    // The unit tests above all use a fake adapter; this one drives the real
    // IO adapter the app builds, so a mistake in the wrapper cannot pass
    // unnoticed and take the whole network layer with it.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(server.first.then((req) {
      req.response
        ..statusCode = 200
        ..write('hello from the origin');
      return req.response.close();
    }));

    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    dio.httpClientAdapter = CallTimeoutAdapter(dio.httpClientAdapter);
    addTearDown(dio.close);

    final res = await dio.get<String>('http://127.0.0.1:${server.port}/x');
    expect(res.statusCode, 200);
    expect(res.data, 'hello from the origin');
  });

  test('a real Dio download streams to disk through the wrapper', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(server.first.then((req) async {
      req.response.statusCode = 200;
      for (var i = 0; i < 20; i++) {
        req.response.add(utf8.encode('chunk$i;'));
        await req.response.flush();
      }
      return req.response.close();
    }));

    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    dio.httpClientAdapter = CallTimeoutAdapter(dio.httpClientAdapter);
    addTearDown(dio.close);

    final target = File(
      '${Directory.systemTemp.createTempSync('mohyeong_ct').path}/page.bin',
    );
    await dio.download('http://127.0.0.1:${server.port}/page.bin', target.path);
    expect(await target.readAsString(),
        [for (var i = 0; i < 20; i++) 'chunk$i;'].join());
  });

  test('closing reaches the inner adapter', () {
    final inner = _FakeAdapter(body: () => const Stream<Uint8List>.empty());
    CallTimeoutAdapter(inner).close(force: true);
    expect(inner.closed, isTrue);
  });
}
