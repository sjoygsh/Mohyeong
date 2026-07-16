import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_js/flutter_js.dart';

import '../../network/webview_http_client.dart';

/// Owns a single JavaScript runtime (one per extension instance) and bridges
/// the host APIs the JS code calls into:
///
///   * `http.get(url, opts)` / `http.post(url, opts)` — returns a Promise of
///     `{ status, body, headers }`.
///   * `console.log/warn/error` — forwarded to Dart via [onLog].
///
/// By default the QuickJS engine runs on a DEDICATED WORKER ISOLATE so the
/// extension's synchronous CPU work (HTML/JSON parsing, regex, DOM walking)
/// never blocks the UI isolate's frame loop. The `http` bridge round-trips
/// back to this (main) isolate because the shared cookie jar / Cloudflare
/// clearance live on the main-isolate [Dio]; `console` is fire-and-forget.
///
/// If the worker can't be created (older engine, FFI/native load failure,
/// non-isolate-safe platform) the runtime transparently falls back to
/// in-process execution — identical to the original behaviour, just on the
/// calling isolate.
///
/// The public surface ([loadExtensionSource], [readManifest], [hasMethod],
/// [setSourcePrefs], [invoke], [dispose]) is unchanged so [JsSource] and the
/// rest of the app are oblivious to where the engine actually runs.
class JsRuntime {
  JsRuntime({required this.dio, this.onLog});

  final Dio dio;
  final void Function(String level, String message)? onLog;

  _JsEngine? _engine;
  Map<String, dynamic> _manifest = const {};
  Set<String> _methods = const {};

  /// Services one `http` request from either engine on the MAIN isolate, so
  /// every extension fetch shares the app's cookie jar / Cloudflare state.
  /// [args] is the JSON string (or decoded map) the JS `http` bridge sends.
  // Short-TTL, success-only response cache for idempotent fetches. Collapses
  // the details()+chapters() double-fetch of the SAME manga page (Madara/
  // MangaThemesia fetch the series URL twice within ~1s of opening a manga).
  // TTL is short so a manual "Refresh from source" still re-fetches.
  static final Map<String, _CachedResp> _respCache = {};

  // In-flight coalescing for idempotent fetches: the response cache only
  // helps a caller that arrives AFTER the first fetch completed. Callers
  // that run concurrently (parallel details()+chapters() of one series URL,
  // the library-update sweep workers) share the same future instead of each
  // firing their own network request.
  static final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  Future<Map<String, dynamic>> serviceHttp(dynamic args) async {
    try {
      final Map<String, dynamic> req = args is String
          ? jsonDecode(args) as Map<String, dynamic>
          : Map<String, dynamic>.from(args as Map);
      final method = (req['method'] as String? ?? 'GET').toUpperCase();
      final url = req['url'] as String;
      final headers = (req['headers'] as Map?)?.cast<String, dynamic>();
      final body = req['body'];
      final idempotent = method == 'GET' || method == 'HEAD';
      final forceWebView = req['webview_force'] == true;
      // webview_settle_ms is the CEILING; webview_ready_js (a JS boolean) lets
      // the proxy return as soon as the expected content exists.
      final settleMs = (req['webview_settle_ms'] as num?)?.toInt();
      final readyJs = req['webview_ready_js'] as String?;
      final settle = settleMs != null
          ? Duration(milliseconds: settleMs.clamp(0, 20000))
          : const Duration(milliseconds: 1800);
      // The render requirements are part of the response's identity: a fetch
      // that must wait for JS-injected content (webview_force / ready_js, e.g.
      // an AJAX-chapters Madara chapters() call) can't be satisfied by a
      // snapshot cached for a plain fetch of the same URL, and vice versa.
      // Identical plain fetches (the Madara details+chapters double-fetch)
      // still share a key and collapse.
      // Headers are part of the identity too: the map is static (shared by
      // every source), and two sources can legitimately GET one CDN URL with
      // different Referer/auth within the TTL.
      final cacheKey =
          '$method $url wv:${forceWebView ? 1 : 0}:${settleMs ?? ''}:${readyJs ?? ''} '
          'h:${headers == null ? 0 : Object.hashAll([
              for (final e in (headers.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
                '${e.key}=${e.value}',
            ])}';
      final webAvail = WebViewHttpClient.instance.isAvailable;

      if (idempotent) {
        final cached = _respCache[cacheKey];
        if (cached != null && cached.isFresh) return cached.value;
        final running = _inflight[cacheKey];
        if (running != null) return await running;
        final future = _fetch(
          method: method,
          url: url,
          headers: headers,
          body: body,
          idempotent: idempotent,
          forceWebView: forceWebView,
          settle: settle,
          readyJs: readyJs,
          cacheKey: cacheKey,
          webAvail: webAvail,
        );
        _inflight[cacheKey] = future;
        try {
          return await future;
        } finally {
          _inflight.remove(cacheKey);
        }
      }

      return await _fetch(
        method: method,
        url: url,
        headers: headers,
        body: body,
        idempotent: idempotent,
        forceWebView: forceWebView,
        settle: settle,
        readyJs: readyJs,
        cacheKey: cacheKey,
        webAvail: webAvail,
      );
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// The actual network dispatch behind [serviceHttp], after the cache and
  /// in-flight-coalescing layers. May throw; [serviceHttp] wraps every path
  /// in the `{'ok': false}` error envelope.
  Future<Map<String, dynamic>> _fetch({
    required String method,
    required String url,
    required Map<String, dynamic>? headers,
    required Object? body,
    required bool idempotent,
    required bool forceWebView,
    required Duration settle,
    required String? readyJs,
    required String cacheKey,
    required bool webAvail,
  }) async {
    // Forced sources (JS-SPA / content the page's own JS injects, e.g. mgeko,
    // Madara admin-ajax chapters): skip the wasted Dio shell fetch (which on a
    // SPA returns an empty page, and on a walled CDN can hang to timeout) and
    // go straight to the JS-running browser. Fall back to Dio if it fails.
    if (forceWebView && idempotent && webAvail) {
      final via = await WebViewHttpClient.instance.request(
        url, method: method, headers: headers, body: body,
        settle: settle, readyJs: readyJs,
      );
      if (via != null) {
        // A snapshot whose readyJs never fired may be content-less (cold
        // WebView burned the settle window on a challenge) — return it so
        // the caller can try parsing, but DON'T cache it: a cached bad
        // snapshot would defeat the caller's retry for the whole TTL.
        if (via['ready'] != false) _cacheStore(cacheKey, via);
        return via;
      }
    }

    final response = await dio.request<dynamic>(
      url,
      data: body,
      options: Options(
        method: method,
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    final status = response.statusCode ?? 0;
    final bodyStr = response.data?.toString() ?? '';

    // Cloudflare fingerprint wall: Dio gets the "Just a moment" challenge even
    // with a valid cf_clearance (TLS/JA3). Retry through the offscreen WebView
    // (real Chromium fingerprint + shared clearance). Idempotent only — Dio
    // already ran, so replaying a POST would double a side effect. (force was
    // handled above; this also covers force when the WebView was unavailable.)
    final challenge = _looksLikeCloudflareChallenge(status, bodyStr);
    if (idempotent && webAvail && (forceWebView || challenge)) {
      final via = await WebViewHttpClient.instance.request(
        url, method: method, headers: headers, body: body,
        settle: settle, readyJs: readyJs,
      );
      if (via != null) {
        // A snapshot whose readyJs never fired may be content-less (cold
        // WebView burned the settle window on a challenge) — return it so
        // the caller can try parsing, but DON'T cache it: a cached bad
        // snapshot would defeat the caller's retry for the whole TTL.
        if (via['ready'] != false) _cacheStore(cacheKey, via);
        return via;
      }
    }

    final result = {
      'ok': true,
      'status': status,
      'body': bodyStr,
      'headers': response.headers.map.map(
        (k, v) => MapEntry(k, v.join(', ')),
      ),
      'final_url': response.realUri.toString(),
    };
    if (idempotent && status >= 200 && status < 300 && !challenge) {
      _cacheStore(cacheKey, result);
    }
    return result;
  }

  void _cacheStore(String key, Map<String, dynamic> value) {
    // Expired entries hold full HTML bodies; drop them now instead of
    // letting them squat in the FIFO until 24 newer responses push them out.
    _respCache.removeWhere((_, cached) => !cached.isFresh);
    _respCache[key] =
        _CachedResp(value, DateTime.now().add(const Duration(seconds: 12)));
    if (_respCache.length > 24) _respCache.remove(_respCache.keys.first);
  }

  /// Heuristic for a Cloudflare interstitial (the JS "Just a moment" / managed
  /// challenge), so we know to retry through the browser engine. Mirrors the
  /// markers Mihon's CloudflareInterceptor checks, plus the challenge-platform
  /// script the interstitial always loads.
  static bool _looksLikeCloudflareChallenge(int status, String body) {
    // The interstitial's <title> is a strong signal at ANY status — Cloudflare
    // sometimes serves the JS challenge with HTTP 200 to XHR/API requests, so
    // a status-gated check alone would miss it and never trigger the retry.
    if (body.contains('<title>Just a moment')) return true;
    if (status != 403 && status != 503 && status != 429) return false;
    return body.contains('challenge-platform') ||
        body.contains('challenge-error') ||
        body.contains('cf-challenge') ||
        body.contains('_cf_chl_opt') ||
        body.contains('window._cf_chl');
  }

  /// Loads the extension source. After this returns, [readManifest] /
  /// [hasMethod] reflect the registered `__extension` (the engine resolves
  /// both at load time so those stay synchronous).
  Future<void> loadExtensionSource(String source) async {
    if (_engine == null) {
      // Prefer the worker isolate; fall back to in-process on any
      // infrastructure failure (spawn, handshake, native load).
      try {
        _engine = await _IsolateEngine.start(this);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('JS worker isolate unavailable, running in-process: $e\n$st');
        }
        _engine = _InProcessEngine(this)..init();
      }
    }
    final result = await _engine!.load(source);
    final manifestStr = result.manifest;
    if (manifestStr == 'null' || manifestStr.isEmpty) {
      throw JsRuntimeException(
        'extension did not register __extension.manifest',
      );
    }
    _manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
    _methods = result.methods.toSet();
  }

  /// The manifest the extension registered into `__extension.manifest`.
  Map<String, dynamic> readManifest() => _manifest;

  /// Whether the extension defines [method] — used for optional contract
  /// methods (e.g. `chapterUrl`) where absence falls back to a Dart default.
  /// Resolved once at load, so this stays synchronous.
  bool hasMethod(String method) => _methods.contains(method);

  /// Pushes the user's per-source settings into the runtime as the
  /// `__sourcePrefs` global (values are all strings). Called after load and
  /// whenever the user changes a setting, so extensions see updates without
  /// a reload.
  void setSourcePrefs(Map<String, String> prefs) {
    _engine?.setSourcePrefs(prefs);
  }

  /// Invokes a method on `__extension` and returns the parsed JSON result.
  /// Arguments are serialised via JSON.stringify, so they must be JSON-safe.
  Future<dynamic> invoke(String method, List<dynamic> args) async {
    final engine = _engine;
    if (engine == null) {
      throw JsRuntimeException('runtime not loaded');
    }
    final str = await engine.invoke(method, args);
    if (str.isEmpty || str == 'undefined') return null;
    return jsonDecode(str);
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }
}

class JsRuntimeException implements Exception {
  JsRuntimeException(this.message);
  final String message;
  @override
  String toString() => 'JsRuntimeException: $message';
}

/// Result of loading an extension: the manifest JSON and the list of method
/// names defined on `__extension` (so `hasMethod` is a local set lookup).
typedef _LoadResult = ({String manifest, List<String> methods});

/// Common surface implemented by the isolate-backed and in-process engines.
abstract class _JsEngine {
  Future<_LoadResult> load(String source);
  Future<String> invoke(String method, List<dynamic> args);
  void setSourcePrefs(Map<String, String> prefs);
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// In-process engine: the original behaviour, kept verbatim as the fallback.
// ---------------------------------------------------------------------------

class _InProcessEngine implements _JsEngine {
  _InProcessEngine(this._host);

  final JsRuntime _host;
  late final JavascriptRuntime _runtime;

  void init() {
    _runtime = getJavascriptRuntime();
    _runtime.enableHandlePromises();
    _runtime.onMessage('http', (dynamic args) => _host.serviceHttp(args));
    _runtime.onMessage('log', (dynamic args) {
      final Map m =
          args is String ? (jsonDecode(args) as Map) : (args as Map);
      _host.onLog?.call(
        m['level'] as String? ?? 'log',
        m['message'] as String? ?? '',
      );
      return null;
    });
    _runtime.evaluate(_preamble);
  }

  @override
  Future<_LoadResult> load(String source) async {
    final result = _runtime.evaluate(source);
    if (result.isError) {
      throw JsRuntimeException('extension load failed: ${result.stringResult}');
    }
    final manifest = _runtime
        .evaluate('JSON.stringify(__extension && __extension.manifest || null)')
        .stringResult;
    final methods = _runtime.evaluate(_methodsExpr).stringResult;
    return (
      manifest: manifest,
      methods: (jsonDecode(methods) as List).cast<String>(),
    );
  }

  @override
  Future<String> invoke(String method, List<dynamic> args) async {
    final resolved = await _runtime
        .handlePromise(await _runtime.evaluateAsync(_invokeExpr(method, args)));
    if (resolved.isError) {
      throw JsRuntimeException('extension.$method failed: ${resolved.stringResult}');
    }
    return resolved.stringResult;
  }

  @override
  void setSourcePrefs(Map<String, String> prefs) {
    _runtime.evaluate('__sourcePrefs = ${jsonEncode(prefs)};');
  }

  @override
  Future<void> dispose() async => _runtime.dispose();
}

// ---------------------------------------------------------------------------
// Isolate engine: QuickJS on a worker isolate, http bridged back to main.
// ---------------------------------------------------------------------------

class _IsolateEngine implements _JsEngine {
  _IsolateEngine._(this._isolate, this._command, this._hostPort);

  final Isolate _isolate;

  /// Worker's command port (also receives http replies, tagged separately).
  final SendPort _command;

  /// Main-side port the worker sends `http`/`log` requests to.
  final ReceivePort _hostPort;

  /// Worker's dedicated port for http replies — separate from the command
  /// channel so a reply can land while the worker is suspended mid-invoke
  /// (the command loop is busy; this is delivered by an independent listen).
  late final SendPort _httpReply;

  static Future<_IsolateEngine> start(JsRuntime host) async {
    final ready = ReceivePort();
    final hostPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _jsWorkerEntry,
      _WorkerBootstrap(ready.sendPort, hostPort.sendPort),
      errorsAreFatal: true,
      debugName: 'js-extension-worker',
    ).timeout(const Duration(seconds: 10));

    // First message from the worker is its {command, httpReply} ports.
    final handshake = await ready.first.timeout(const Duration(seconds: 10))
        as List;
    ready.close();
    final engine = _IsolateEngine._(isolate, handshake[0] as SendPort, hostPort)
      .._httpReply = handshake[1] as SendPort;

    // Service the worker's http/log requests on this (main) isolate.
    hostPort.listen((dynamic msg) async {
      final m = msg as Map;
      switch (m['k']) {
        case 'http':
          final res = await host.serviceHttp(m['req']);
          engine._httpReply.send({'id': m['id'], 'res': res});
        case 'log':
          final lm = jsonDecode(m['msg'] as String) as Map;
          host.onLog?.call(
            lm['level'] as String? ?? 'log',
            lm['message'] as String? ?? '',
          );
      }
    });
    return engine;
  }

  /// Sends a command carrying a one-shot reply port and awaits its result,
  /// converting a worker-side error into a [JsRuntimeException].
  Future<Map> _send(Map cmd) async {
    final reply = ReceivePort();
    _command.send({...cmd, 'reply': reply.sendPort});
    final result = await reply.first as Map;
    reply.close();
    if (result['error'] != null) {
      throw JsRuntimeException(result['error'] as String);
    }
    return result;
  }

  @override
  Future<_LoadResult> load(String source) async {
    final r = await _send({'cmd': 'load', 'source': source});
    return (
      manifest: r['manifest'] as String,
      methods: (r['methods'] as List).cast<String>(),
    );
  }

  @override
  Future<String> invoke(String method, List<dynamic> args) async {
    final r = await _send({'cmd': 'invoke', 'method': method, 'args': args});
    return r['result'] as String;
  }

  @override
  void setSourcePrefs(Map<String, String> prefs) {
    // Fire-and-forget; the worker applies it in command order before the
    // next invoke.
    _command.send({'cmd': 'setPrefs', 'json': jsonEncode(prefs)});
  }

  @override
  Future<void> dispose() async {
    _command.send({'cmd': 'dispose'});
    _hostPort.close();
    // Give the worker a tick to tear down its runtime, then kill it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// Sendable bootstrap handed to the worker isolate.
class _WorkerBootstrap {
  const _WorkerBootstrap(this.ready, this.hostPort);
  final SendPort ready;
  final SendPort hostPort;
}

/// Worker isolate entry point. Hosts the QuickJS runtime; bridges `http`
/// back to the main isolate (so cookies/Cloudflare are shared) and runs the
/// extension's synchronous work off the UI isolate.
/// A cached idempotent HTTP response with a short freshness window (see the
/// serviceHttp double-fetch collapse).
class _CachedResp {
  final Map<String, dynamic> value;
  final DateTime expiry;
  _CachedResp(this.value, this.expiry);
  bool get isFresh => DateTime.now().isBefore(expiry);
}

@pragma('vm:entry-point')
Future<void> _jsWorkerEntry(_WorkerBootstrap boot) async {
  // xhr:false skips flutter_js's fetch/XHR extension, whose setup needs the
  // root-isolate binary messenger (absent on a worker isolate) and otherwise
  // throws during init. Extensions use our custom `http` bridge, not fetch.
  final runtime = getJavascriptRuntime(xhr: false);
  runtime.enableHandlePromises();

  final command = ReceivePort();
  final httpReply = ReceivePort();
  final pending = <int, Completer<dynamic>>{};
  var seq = 0;

  // http requests round-trip to main; the reply lands on httpReply (a
  // separate port) so it's processed even while the command loop is
  // suspended awaiting handlePromise mid-invoke.
  runtime.onMessage('http', (dynamic args) {
    final id = seq++;
    final c = Completer<dynamic>();
    pending[id] = c;
    boot.hostPort.send({
      'k': 'http',
      'id': id,
      'req': args is String ? args : jsonEncode(args),
    });
    return c.future;
  });
  httpReply.listen((dynamic msg) {
    final m = msg as Map;
    pending.remove(m['id'])?.complete(m['res']);
  });

  runtime.onMessage('log', (dynamic args) {
    boot.hostPort.send({
      'k': 'log',
      'msg': args is String ? args : jsonEncode(args),
    });
    return null;
  });

  runtime.evaluate(_preamble);

  // Hand the main isolate our command + http-reply ports.
  boot.ready.send([command.sendPort, httpReply.sendPort]);

  await for (final msg in command) {
    final cmd = msg as Map;
    final reply = cmd['reply'] as SendPort?;
    try {
      switch (cmd['cmd']) {
        case 'load':
          final res = runtime.evaluate(cmd['source'] as String);
          if (res.isError) {
            throw JsRuntimeException('extension load failed: ${res.stringResult}');
          }
          final manifest = runtime
              .evaluate(
                  'JSON.stringify(__extension && __extension.manifest || null)')
              .stringResult;
          final methods = runtime.evaluate(_methodsExpr).stringResult;
          reply!.send({
            'manifest': manifest,
            'methods': (jsonDecode(methods) as List).cast<String>(),
          });
        case 'invoke':
          final resolved = await runtime.handlePromise(await runtime
              .evaluateAsync(
                  _invokeExpr(cmd['method'] as String, cmd['args'] as List)));
          if (resolved.isError) {
            throw JsRuntimeException(
                'extension.${cmd['method']} failed: ${resolved.stringResult}');
          }
          reply!.send({'result': resolved.stringResult});
        case 'setPrefs':
          runtime.evaluate('__sourcePrefs = ${cmd['json']};');
        case 'dispose':
          command.close();
          httpReply.close();
          runtime.dispose();
          return;
      }
    } catch (e) {
      reply?.send({'error': e.toString()});
    }
  }
}

/// JS that returns the JSON array of function-valued keys on `__extension`,
/// so the Dart side can answer `hasMethod` without per-call round-trips.
const String _methodsExpr =
    'JSON.stringify(__extension ? Object.keys(__extension)'
    '.filter(function(k){return typeof __extension[k]==="function";}) : [])';

/// JS that awaits `__extension.<method>(...args)` and JSON-stringifies the
/// result. Args are JSON-encoded into the call.
String _invokeExpr(String method, List<dynamic> args) =>
    '(async()=>{const r=await __extension.$method(...${jsonEncode(args)});'
    'return JSON.stringify(r);})()';

/// JS preamble installed into every extension runtime. Defines the globals
/// extensions are expected to use:
///
///   * `http.get(url, opts?)` / `http.post(url, opts?)` -> Promise of Response
///     where Response = `{ ok, status, body, headers, final_url }`.
///     `opts` may include { headers, body }.
///   * `console.log/warn/error` -> Dart's onLog callback.
///
/// Extensions must assign their definition to the global `__extension` after
/// defining their methods (manifest + popular/latest/search/details/chapters/
/// pages). See `assets/extension_api.js` (loaded via this preamble) for the
/// expected shape.
const String _preamble = r'''
var __extension = null;
// Per-source user settings (optional `preferences()` contract): the host
// injects the stored picks here before/after method calls; extensions read
// e.g. `__sourcePrefs.data_saver === 'true'`.
var __sourcePrefs = {};
var http = {
  get: function(url, opts) {
    var payload = JSON.stringify(Object.assign({method:'GET', url:url}, opts||{}));
    return sendMessage('http', payload).then(function(r) {
      return typeof r === 'string' ? JSON.parse(r) : r;
    });
  },
  post: function(url, opts) {
    var payload = JSON.stringify(Object.assign({method:'POST', url:url}, opts||{}));
    return sendMessage('http', payload).then(function(r) {
      return typeof r === 'string' ? JSON.parse(r) : r;
    });
  },
};
var console = {
  log:   function(){ sendMessage('log', JSON.stringify({level:'log',   message: Array.prototype.join.call(arguments, ' ')})); },
  warn:  function(){ sendMessage('log', JSON.stringify({level:'warn',  message: Array.prototype.join.call(arguments, ' ')})); },
  error: function(){ sendMessage('log', JSON.stringify({level:'error', message: Array.prototype.join.call(arguments, ' ')})); },
};
''';
