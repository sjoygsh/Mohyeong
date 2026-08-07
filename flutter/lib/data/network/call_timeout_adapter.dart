import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Wraps another [HttpClientAdapter] to put a ceiling on a WHOLE call, the way
/// Kotlin `NetworkHelper` does with OkHttp's `callTimeout(2, MINUTES)`.
///
/// Dio has no equivalent. Its `connectTimeout` covers dialling and its
/// `receiveTimeout` — for a streamed response, which is what a page download
/// is — measures the gap between chunks, not the whole transfer. A server that
/// dribbles a few bytes every twenty seconds therefore satisfies both forever.
/// Now that at most one chapter per source downloads at a time, one host stuck
/// like that stalls that source's queue with nothing to time it out.
///
/// The deadline covers dialling and the body together: whatever the response
/// headers left of the budget is what the body gets. The body's clock is a
/// single timer over the whole stream rather than a per-chunk one, which is
/// the point — a per-chunk timer is what Dio already has.
class CallTimeoutAdapter implements HttpClientAdapter {
  CallTimeoutAdapter(
    this._inner, {
    this.callTimeout = const Duration(minutes: 2),
  });

  final HttpClientAdapter _inner;
  final Duration callTimeout;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final spent = Stopwatch()..start();
    final ResponseBody body;
    try {
      body = await _inner.fetch(options, requestStream, cancelFuture).timeout(
            callTimeout,
            onTimeout: () => throw DioException.connectionTimeout(
              timeout: callTimeout,
              requestOptions: options,
            ),
          );
    } on TimeoutException {
      // `onTimeout` above throws, so this is only reachable if an inner
      // adapter surfaces its own; report it in the shape callers classify.
      throw DioException.connectionTimeout(
        timeout: callTimeout,
        requestOptions: options,
      );
    }

    final remaining = callTimeout - spent.elapsed;
    if (remaining <= Duration.zero) {
      throw DioException.receiveTimeout(
        timeout: callTimeout,
        requestOptions: options,
      );
    }

    return ResponseBody(
      _deadline(body.stream, remaining, options),
      body.statusCode,
      statusMessage: body.statusMessage,
      isRedirect: body.isRedirect,
      redirects: body.redirects,
      headers: body.headers,
    );
  }

  /// [source] re-emitted, failing if it has not finished within [remaining].
  ///
  /// Pause and resume are forwarded: a download writes to disk and pauses the
  /// stream when the sink is busy, and swallowing that would buffer a whole
  /// chapter page in memory. The timer keeps running while paused, which is
  /// correct — it is a deadline on the call, not on throughput.
  Stream<Uint8List> _deadline(
    Stream<Uint8List> source,
    Duration remaining,
    RequestOptions options,
  ) {
    late final StreamController<Uint8List> controller;
    StreamSubscription<Uint8List>? sub;
    Timer? timer;

    void cleanUp() {
      timer?.cancel();
      timer = null;
    }

    controller = StreamController<Uint8List>(
      onListen: () {
        timer = Timer(remaining, () {
          sub?.cancel();
          sub = null;
          if (!controller.isClosed) {
            controller.addError(
              DioException.receiveTimeout(
                timeout: callTimeout,
                requestOptions: options,
              ),
            );
            controller.close();
          }
        });
        sub = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            cleanUp();
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        cleanUp();
        final s = sub;
        sub = null;
        return s?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
