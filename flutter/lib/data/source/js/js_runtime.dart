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
    _runtime.evaluate(_mhThemeLib);
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

  /// Completes when [dispose] runs. In-flight [_send] calls race against it:
  /// the runtime is shared and cached per source, so an uninstall/update can
  /// land while another screen is mid-`invoke`. Killing the worker would
  /// otherwise strand that reply forever — nobody is left to send it.
  final Completer<void> _disposed = Completer<void>();

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
    if (_disposed.isCompleted) {
      throw JsRuntimeException('JS runtime was disposed');
    }
    final reply = ReceivePort();
    _command.send({...cmd, 'reply': reply.sendPort});
    // Losing the race means the worker died owing us this reply; surface it
    // as a normal failure so callers fall into their error state instead of
    // awaiting a future that can never complete.
    final result = await Future.any<Map>([
      reply.first.then((v) => v as Map),
      _disposed.future.then(
        (_) => <String, dynamic>{'error': 'JS runtime was disposed'},
      ),
    ]);
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
    if (_disposed.isCompleted) return;
    // Fail anyone mid-invoke BEFORE the worker dies, not after.
    _disposed.complete();
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
  runtime.evaluate(_mhThemeLib);

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

/// Shared Mihon-theme factory library, evaluated after [_preamble] in both
/// the main-isolate and worker-isolate runtimes. See the JS header for the
/// contract; kept in sync with scratchpad mh_std.js via the parity harness.
const String _mhThemeLib = r'''
// Shared Mihon-theme library injected after the preamble. Factory-based
// extensions register as e.g. `__extension = mh.themes.Madara({base,id,name})`
// instead of copy-pasting the whole theme body. Standalone extensions that
// don't reference `mh` are unaffected. Helper/theme bodies are the same code
// the standalone Madara clones ran, lifted verbatim (proven byte-identical by
// the parity/replay harness).
var mh = (function () {
  // Shared UA — byte-identical across all 26 files today.
  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  // ---- BASE-independent shared helpers (identical across ~25 files today) --
  var _attrRe = {};
  function attr(tag, name) {
    if (!tag) return null;
    var re = _attrRe[name];
    if (!re) {
      re = _attrRe[name] = [
        new RegExp('(?:^|[^-\\w])' + name + '\\s*=\\s*"([^"]*)"'),
        new RegExp('(?:^|[^-\\w])' + name + "\\s*=\\s*'([^']*)'"),
      ];
    }
    var m = re[0].exec(tag);
    if (m) return m[1];
    m = re[1].exec(tag);
    return m ? m[1] : null;
  }
  function pickCover(s) {
    if (!s) return null;
    var cands = [attr(s, 'data-src'), attr(s, 'data-lazy-src'),
                 attr(s, 'src'), attr(s, 'data-backup')];
    var fallback = null;
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      if (!c) continue;
      c = c.replace(/^\s+|\s+$/g, '').split(/\s+/)[0];
      if (!c || /placeholder|blank|lazy|spinner|loading|^data:image/i.test(c)) continue;
      if (fallback == null) fallback = c;
      if (/^https?:\/\//.test(c)) return c;
    }
    return fallback;
  }
  var ENTITIES = {
    '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#039;': "'",
    '&#39;': "'", '&apos;': "'", '&nbsp;': ' ', '&rsquo;': '’', '&lsquo;': '‘',
    '&hellip;': '…', '&mdash;': '—', '&ndash;': '–',
  };
  function decode(s) {
    if (!s) return s;
    return s.replace(/&[a-z#0-9]+;/gi, function (e) {
      if (ENTITIES[e] != null) return ENTITIES[e];
      var m = /^&#(\d+);$/.exec(e);
      var cp = m ? parseInt(m[1], 10)
        : ((m = /^&#x([0-9a-f]+);$/i.exec(e)) ? parseInt(m[1], 16) : -1);
      if (cp < 0) return e;
      return String.fromCodePoint ? String.fromCodePoint(cp) : String.fromCharCode(cp);
    });
  }
  function stripTags(s) {
    return s ? s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() : s;
  }

  // ---- Madara theme factory (mirrors Mihon's abstract Madara.kt) -----------
  // config: { base, id, name, lang, mangaPath?, cardPathRe?, ajaxChapters? }
  function Madara(config) {
    var BASE = config.base;
    var MPATH = config.mangaPath || 'manga';
    // Card-anchor path alternation. Default 'manga' == the narrow tight-cluster
    // regex; looser clones pass e.g. 'manga|manhua|manhwa|comics?|series'.
    var CARD = config.cardPathRe || 'manga';
    var cardRe = new RegExp('<a\\s+[^>]*href="([^"]*\\/(?:' + CARD + ')\\/[^"]+)"[^>]*>');

    function abs(url) {
      if (!url) return url;
      if (url.indexOf('//') === 0) return 'https:' + url;
      if (url.indexOf('http') === 0) return url;
      if (url.charAt(0) === '/') return BASE + url;
      return BASE + '/' + url;
    }
    function getHtml(url, opts) {
      var o = opts || {};
      o.headers = o.headers || {};
      if (!o.headers.Referer) o.headers.Referer = BASE + '/';
      return http.get(url, o).then(function (r) {
        if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
        if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
        return r.body || '';
      });
    }
    function postHtml(url, body) {
      return http.post(url, {
        headers: {
          Referer: BASE + '/',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: body,
      }).then(function (r) {
        if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
        if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status);
        return r.body || '';
      });
    }

    function parseList(html) {
      var out = [];
      var blocks = html.split('page-item-detail');
      for (var i = 1; i < blocks.length; i++) {
        var b = blocks[i];
        var aM = cardRe.exec(b);
        if (!aM) continue;
        var url = aM[1];
        var imgM = /<img\b[^>]*>/.exec(b);
        var imgTag = imgM ? imgM[0] : null;
        var cover = pickCover(imgTag);
        var title = null;
        var tM = /post-title[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
        if (tM) title = stripTags(tM[1]);
        if (!title) title = attr(aM[0], 'title') || '';
        out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
      }
      return out;
    }
    function parseSearch(html) {
      var out = [];
      var blocks = html.split(/class="[^"]*c-tabs-item__content/);
      for (var i = 1; i < blocks.length; i++) {
        var b = blocks[i];
        var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
        if (!aM) continue;
        var imgM = /<img\b[^>]*>/.exec(b);
        var imgTag = imgM ? imgM[0] : null;
        var cover = pickCover(imgTag);
        var tM = /post-title[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
        var title = tM ? stripTags(tM[1]) : (attr(aM[0], 'title') || '');
        out.push({ url: abs(aM[1]), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
      }
      return out;
    }
    function hasNext(html, page) {
      return (/class="[^"]*nav-previous|wp-pagenavi|class="[^"]*next page-numbers|m_orderby=[^"]*&(amp;)?page=|\/page\/(\d+)/i.test(html) &&
        html.indexOf('/page/' + (page + 1)) !== -1) || /next page-numbers|nav-previous/i.test(html);
    }
    function listUrl(orderby, page) {
      return page <= 1
        ? BASE + '/' + MPATH + '/?m_orderby=' + orderby
        : BASE + '/' + MPATH + '/page/' + page + '/?m_orderby=' + orderby;
    }
    // Readiness predicates for the WebView retry. These matter ONLY when Dio
    // hit a Cloudflare challenge and the browser took over: without one, the
    // proxy snapshots as soon as the DOM node count stops growing, which on a
    // walled Madara listing happens while the cards are still on their way.
    // manhwatop proved it — a Dev page-source dump of ?m_orderby=views showed
    // 15 page-item-detail blocks, while the source's own Popular tab showed
    // "No results found" off a snapshot taken too early. Latest looked fine
    // only because it comes back faster. A ceiling, not a floor: a page that
    // is already there returns immediately.
    var LIST_OPTS = {
      webview_ready_js: "!!document.querySelector('.page-item-detail')",
      webview_settle_ms: 12000,
    };
    // Search waits for the RESULT rows only. A Madara search page also carries
    // a sidebar of page-item-detail cards, so accepting those as "ready" fires
    // the predicate on furniture that is present from the first paint, while
    // the results are still loading — a manhwatop dump of ?s=king showed 12
    // c-tabs-item__content results next to sidebar page-item-detail cards.
    var SEARCH_OPTS = {
      webview_ready_js: "!!document.querySelector('.c-tabs-item__content')",
      webview_settle_ms: 12000,
    };
    function popular(page) {
      return getHtml(listUrl('views', page), LIST_OPTS).then(function (html) {
        return { mangas: parseList(html), has_next_page: hasNext(html, page) };
      });
    }
    function latest(page) {
      return getHtml(listUrl('latest', page), LIST_OPTS).then(function (html) {
        return { mangas: parseList(html), has_next_page: hasNext(html, page) };
      });
    }
    function search(query, page) {
      var q = encodeURIComponent(query || '');
      var url = (page <= 1 ? BASE + '/?s=' : BASE + '/page/' + page + '/?s=') +
        q + '&post_type=wp-manga';
      return getHtml(url, SEARCH_OPTS).then(function (html) {
        var mangas = parseSearch(html);
        // The listing fallback is for Madara clones whose search results come
        // back as page-item-detail cards. On a site that DOES use c-tabs rows,
        // an empty parse means the search genuinely matched nothing, and
        // falling through would answer the query with the sidebar's cards —
        // a wrong answer reads far worse than an honest empty one.
        if (mangas.length === 0 && html.indexOf('c-tabs-item') < 0) {
          mangas = parseList(html);
        }
        return { mangas: mangas, has_next_page: hasNext(html, page) };
      });
    }

    // ---- details ----
    function mapStatus(s) {
      s = (s || '').toLowerCase();
      if (s.indexOf('ongoing') >= 0 || s.indexOf('publishing') >= 0) return 1;
      if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
      if (s.indexOf('hiatus') >= 0 || s.indexOf('on hold') >= 0) return 6;
      if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
      return 0;
    }
    function linksText(block) {
      var out = [];
      if (!block) return out;
      var re = /<a[^>]*>([\s\S]*?)<\/a>/g, m;
      while ((m = re.exec(block)) !== null) {
        var t = stripTags(m[1]);
        if (t) out.push(decode(t));
      }
      return out;
    }
    function section(html, cls) {
      var m = new RegExp('class="' + cls + '"[^>]*>([\\s\\S]*?)</div>').exec(html);
      return m ? m[1] : null;
    }
    function details(manga) {
      return getHtml(abs(manga.url)).then(function (html) {
        var titleM = /<div class="post-title">[\s\S]*?<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/.exec(html);
        var title = titleM ? decode(stripTags(titleM[1])) : (manga.title || '');
        var picM = /class="summary_image"[\s\S]*?<img\b([^>]*)>/.exec(html);
        var cover = picM ? pickCover(picM[1]) : null;
        var author = linksText(section(html, 'author-content')).join(', ') || null;
        var artist = linksText(section(html, 'artist-content')).join(', ') || null;
        var genres = linksText(section(html, 'genres-content'));
        var status = 0;
        var stM = /<div class="summary-heading">\s*<h5[^>]*>\s*Status[\s\S]*?<div class="summary-content">([\s\S]*?)<\/div>/i.exec(html);
        if (stM) status = mapStatus(stripTags(stM[1]));
        var description = null;
        var dM = /class="(?:summary__content|description-summary)"[^>]*>([\s\S]*?)<\/div>/.exec(html);
        if (dM) description = decode(stripTags(dM[1].replace(/<h[0-9][\s\S]*?<\/h[0-9]>/g, '')));
        return {
          url: manga.url, title: title, author: author, artist: artist,
          description: description, genre: genres.length ? genres.join(', ') : null,
          status: status,
          thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
          initialized: true,
        };
      });
    }

    // ---- chapters ----
    function parseRelativeDate(text) {
      text = text || '';
      var MS = { second: 1e3, minute: 6e4, hour: 36e5, day: 864e5, week: 6048e5,
        month: 2629746e3, year: 31556952e3 };
      var m = /(\d+)\s*(second|minute|hour|day|week|month|year)/i.exec(text);
      if (m) return Date.now() - parseInt(m[1], 10) * (MS[m[2].toLowerCase()] || 0);
      m = /\b(?:last|an?)\s+(second|minute|hour|day|week|month|year)\b/i.exec(text);
      if (m) return Date.now() - (MS[m[1].toLowerCase()] || 0);
      if (/\byesterday\b/i.test(text)) return Date.now() - 864e5;
      if (/\b(?:just now|today)\b/i.test(text)) return Date.now();
      return 0;
    }
    function parseChapters(html) {
      var out = [];
      var seen = {};
      var blocks = html.split(/<li[^>]*class="[^"]*wp-manga-chapter/);
      for (var i = 1; i < blocks.length; i++) {
        var b = blocks[i];
        var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(b);
        if (!aM) continue;
        var url = aM[1];
        if (!/^https?:|^\//.test(url) || seen[url]) continue;
        seen[url] = true;
        var name = stripTags(aM[2]);
        var dM = /chapter-release-date[\s\S]*?>([\s\S]*?)<\/(?:i|a|span)>/.exec(b);
        var date = 0;
        if (dM) {
          var t = stripTags(dM[1]);
          var parsed = Date.parse(t);
          if (!isNaN(parsed)) date = parsed;
          else date = parseRelativeDate(t);
        }
        out.push({ url: abs(url), name: decode(name) || url, date_upload: date, chapter_number: -1 });
      }
      return out;
    }
    // Three chapter-list strategies, picked by config.chapterMode:
    //   'inline'   (default) the series page ships the list in the HTML.
    //   'ajaxPost'  POST {mangaUrl}/ajax/chapters/ — the stock Madara endpoint,
    //               correct on non-CF sites (the tight cluster uses it).
    //   'webview'   force the series page through the JS-running WebView proxy
    //               and parse the list it renders. Needed where the site's own
    //               admin-ajax action requires a POST+nonce (which cannot ride
    //               the proxy) AND a plain GET returns an un-rendered shell.
    // `ajaxChapters: true` is kept as the legacy alias for 'ajaxPost'.
    var CHAPTER_MODE = config.chapterMode ||
      (config.ajaxChapters ? 'ajaxPost' : 'inline');
    function chapters(manga) {
      if (CHAPTER_MODE === 'ajaxPost') {
        var u = abs(manga.url).replace(/\/+$/, '') + '/ajax/chapters/';
        return postHtml(u, '').then(parseChapters);
      }
      if (CHAPTER_MODE === 'webview') {
        return getHtml(abs(manga.url), {
          webview_force: true,
          webview_settle_ms: config.chapterSettleMs || 8000,
          webview_ready_js: "document.querySelectorAll('.wp-manga-chapter').length>0",
        }).then(parseChapters);
      }
      return getHtml(abs(manga.url)).then(parseChapters);
    }

    // ---- pages ----
    function pages(chapter) {
      return getHtml(abs(chapter.url)).then(function (html) {
        var start = html.indexOf('reading-content');
        var region = start >= 0 ? html.substring(start) : html;
        var out = [];
        var seen = {};
        var re = /<img\b([^>]*)>/g, m, idx = 0;
        while ((m = re.exec(region)) !== null) {
          var tag = m[1];
          var src = attr(tag, 'data-src') || attr(tag, 'src');
          if (!src) continue;
          src = src.replace(/^\s+|\s+$/g, '');
          if (src.indexOf('//') === 0) src = 'https:' + src;
          if (src.indexOf('http') !== 0) continue;
          if (/\/themes\/|logo|loading|dflazy|avatar|gravatar/i.test(src)) continue;
          if (seen[src]) continue;
          seen[src] = true;
          out.push({
            index: idx++, url: src, image_url: src,
            headers: { Referer: BASE + '/', 'User-Agent': UA },
          });
        }
        return out;
      });
    }
    function chapterUrl(chapter) { return abs(chapter.url); }

    return {
      manifest: {
        id: config.id, name: config.name, lang: config.lang || 'en',
        base_url: BASE,
        version_code: config.versionCode || 1,
        supports_latest: config.supportsLatest !== false,
      },
      popular: popular, latest: latest, search: search,
      details: details, chapters: chapters, pages: pages, chapterUrl: chapterUrl,
      // Helper bag for stubs that keep the theme but override ONE method (e.g.
      // harimanga's JSON chapter API). Overrides call these instead of
      // re-inlining the fetch/normalise logic; the host ignores extra keys.
      _h: { abs: abs, getHtml: getHtml, postHtml: postHtml,
            parseList: parseList, parseChapters: parseChapters },
    };
  }

  // ---- MangaThemesia (WPMangaStream) factory ------------------------------
  // config: { base, id, name, lang?, dir?, versionCode?, supportsLatest? }
  // `dir` is the browse sub-directory (rizzfables /series, thunderscans
  // /comics, toongod /manga). Body lifted verbatim from the standalone clones;
  // their extra `&#58;`/`&#038;` ENTITIES fast-paths are dropped because the
  // shared decode() resolves both through its generic numeric branch to the
  // same characters (parity-verified on live HTML).
  function MangaThemesia(config) {
    var BASE = config.base;
    var DIR = config.dir || 'manga';

    function abs(url) {
      if (!url) return url;
      if (url.indexOf('//') === 0) return 'https:' + url;
      if (url.indexOf('http') === 0) return url;
      if (url.charAt(0) === '/') return BASE + url;
      return BASE + '/' + url;
    }
    function getHtml(url) {
      return http.get(url, { headers: { Referer: BASE + '/' } }).then(function (r) {
        if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
        if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
        return r.body || '';
      });
    }

    // Card: div.bsx > a[href][title] + img.ts-post-image[src|data-src].
    function parseList(html) {
      var out = [];
      var seen = {};
      var blocks = html.split(/class="bsx[^"]*"/);
      for (var i = 1; i < blocks.length; i++) {
        var b = blocks[i];
        var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
        if (!aM) continue;
        var url = aM[1];
        if (url.indexOf('/series/') < 0 && url.indexOf('/manga/') < 0 &&
            url.indexOf('/komik/') < 0 && url.indexOf('/comics/') < 0) {
          continue;
        }
        if (seen[url]) continue;
        seen[url] = true;
        var imgM = /<img\b[^>]*>/.exec(b);
        var imgTag = imgM ? imgM[0] : null;
        var cover = attr(imgTag, 'data-src') || attr(imgTag, 'data-lazy-src') || attr(imgTag, 'src');
        var title = attr(aM[0], 'title');
        if (!title && imgTag) title = attr(imgTag, 'title') || attr(imgTag, 'alt');
        out.push({ url: abs(url), title: decode(title || ''), thumbnail_url: cover ? abs(cover) : null });
      }
      return out;
    }
    function hasNext(html, page) {
      // An explicit "next" affordance is proof on its own.
      if (/class="[^"]*r"[^>]*>\s*<a[^>]*href[^>]*>\s*Next|hpage|<a class="next page-numbers"/i.test(html)) return true;
      // A paginator on its own proves nothing: the LAST page renders one too,
      // listing every page back to 1. Matching any /page/N (as this used to)
      // therefore returned true forever, so browse never stopped asking for
      // more and refetched the final page on every scroll. Only a link to the
      // NEXT page counts. The Madara factory above already works this way.
      return html.indexOf('page=' + (page + 1)) !== -1 ||
        html.indexOf('/page/' + (page + 1)) !== -1;
    }
    function popular(page) {
      return getHtml(BASE + '/' + DIR + '/?page=' + page + '&order=popular').then(function (html) {
        return { mangas: parseList(html), has_next_page: hasNext(html, page) };
      });
    }
    function latest(page) {
      return getHtml(BASE + '/' + DIR + '/?page=' + page + '&order=update').then(function (html) {
        return { mangas: parseList(html), has_next_page: hasNext(html, page) };
      });
    }
    function search(query, page) {
      // Page 1 uses the canonical root ?s= URL (the /page/1/ hop can drop the
      // query on some WP sites).
      var url = (page <= 1 ? BASE + '/?s=' : BASE + '/page/' + page + '/?s=') +
        encodeURIComponent(query || '');
      return getHtml(url).then(function (html) {
        return { mangas: parseList(html), has_next_page: hasNext(html, page) };
      });
    }

    function mapStatus(s) {
      s = (s || '').toLowerCase();
      if (s.indexOf('ongoing') >= 0 || s.indexOf('publishing') >= 0) return 1;
      if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
      if (s.indexOf('hiatus') >= 0) return 6;
      if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
      return 0;
    }
    function details(manga) {
      return getHtml(abs(manga.url)).then(function (html) {
        var title = '';
        var ogt = /<meta property="og:title" content="([^"]*)"/.exec(html);
        if (ogt) title = ogt[1].replace(/\s*[-|–]\s*[^-|–]+$/, '');
        if (!title) {
          var h1 = /<h1[^>]*class="entry-title"[^>]*>([\s\S]*?)<\/h1>/.exec(html);
          title = h1 ? stripTags(h1[1]) : (manga.title || '');
        }
        var picM = /class="thumb"[\s\S]*?<img\b([^>]*)>/.exec(html);
        var cover = picM ? (attr(picM[1], 'data-src') || attr(picM[1], 'src')) : null;

        var genres = [];
        var gM = /class="mgen"[^>]*>([\s\S]*?)<\/span>/.exec(html) ||
          /class="seriestugenre"[^>]*>([\s\S]*?)<\/span>/.exec(html);
        if (gM) {
          var gre = /<a[^>]*>([\s\S]*?)<\/a>/g, gm;
          while ((gm = gre.exec(gM[1])) !== null) {
            var g = stripTags(gm[1]); if (g) genres.push(decode(g));
          }
        }

        // "Status" label followed by the value in an i/a/span (covers the
        // .imptdt and .tsinfo variants across MangaThemesia sites).
        var status = 0;
        var stM = /Status[\s\S]{0,40}?<(?:i|a|span)[^>]*>([^<]+)</i.exec(html);
        if (stM) status = mapStatus(stM[1]);

        // Author: a block whose class contains "author" (its first link/value),
        // or an "Author" label followed by the value.
        var author = null;
        var auM = /class="[^"]*author[^"]*"[\s\S]{0,80}?<(?:a|i|span)[^>]*>([^<]+)<\/(?:a|i|span)>/i.exec(html) ||
          /Author[\s\S]{0,40}?<(?:i|a|span)[^>]*>([^<]+)</i.exec(html);
        if (auM) {
          var au = decode(auM[1].trim());
          if (au && au.toLowerCase() !== 'author' && au !== '-') author = au;
        }

        var description = null;
        var dM = /itemprop="description"[^>]*>([\s\S]*?)<\/div>/.exec(html) ||
          /class="entry-content[^"]*"[^>]*>([\s\S]*?)<\/div>/.exec(html);
        if (dM) description = decode(stripTags(dM[1]));

        return {
          url: manga.url,
          title: decode(title),
          author: author,
          artist: null,
          description: description,
          genre: genres.length ? genres.join(', ') : null,
          status: status,
          thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
          initialized: true,
        };
      });
    }

    // div#chapterlist li > a[href] (+ .chapternum name, .chapterdate date).
    // Skip the hidden template entry (data-num="{{number}}" / href with {{ #).
    function chapters(manga) {
      return getHtml(abs(manga.url)).then(function (html) {
        var start = html.indexOf('id="chapterlist"');
        var region = start >= 0 ? html.substring(start) : html;
        var out = [];
        var seen = {};
        var lis = region.split('<li');
        for (var i = 1; i < lis.length; i++) {
          var b = lis[i];
          var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
          if (!aM) continue;
          var url = aM[1];
          if (url.indexOf('{{') >= 0 || url.charAt(0) === '#' || !/^https?:|^\//.test(url)) continue;
          if (seen[url]) continue;
          seen[url] = true;
          var nM = /class="chapternum"[^>]*>([\s\S]*?)<\/span>/.exec(b);
          var name = nM ? stripTags(nM[1]) : '';
          var dM = /class="chapterdate"[^>]*>([\s\S]*?)<\/span>/.exec(b);
          var date = 0;
          if (dM) { var p = Date.parse(stripTags(dM[1])); if (!isNaN(p)) date = p; }
          out.push({ url: abs(url), name: decode(name) || url, date_upload: date, chapter_number: -1 });
        }
        return out;
      });
    }

    // div#readerarea img[src|data-src]; fall back to the ts_reader.run({…})
    // JSON some MangaThemesia sites use instead of inline images.
    function pages(chapter) {
      return getHtml(abs(chapter.url)).then(function (html) {
        var out = [];
        var seen = {};
        var idx = 0;
        var start = html.indexOf('id="readerarea"');
        if (start >= 0) {
          var region = html.substring(start);
          var end = region.indexOf('</div>\n');
          var re = /<img\b([^>]*)>/g, m;
          while ((m = re.exec(region)) !== null) {
            if (end > 0 && m.index > end + 2000) break;
            var src = attr(m[1], 'data-src') || attr(m[1], 'src');
            if (!src) continue;
            src = src.replace(/^\s+|\s+$/g, '');
            if (src.indexOf('//') === 0) src = 'https:' + src;
            if (src.indexOf('http') !== 0) continue;
            if (/\/themes\/|logo|loading|avatar|gravatar/i.test(src)) continue;
            if (seen[src]) continue; seen[src] = true;
            out.push({ index: idx++, url: src, image_url: src, headers: { Referer: BASE + '/', 'User-Agent': UA } });
          }
        }
        if (out.length === 0) {
          var tr = /ts_reader\.run\((\{[\s\S]*?\})\);/.exec(html);
          if (tr) {
            try {
              var data = JSON.parse(tr[1]);
              var imgs = (data.sources && data.sources[0] && data.sources[0].images) || [];
              for (var j = 0; j < imgs.length; j++) {
                out.push({ index: j, url: imgs[j], image_url: imgs[j], headers: { Referer: BASE + '/', 'User-Agent': UA } });
              }
            } catch (e) { /* ignore */ }
          }
        }
        return out;
      });
    }
    function chapterUrl(chapter) { return abs(chapter.url); }

    return {
      manifest: {
        id: config.id, name: config.name, lang: config.lang || 'en',
        base_url: BASE,
        version_code: config.versionCode || 1,
        supports_latest: config.supportsLatest !== false,
      },
      popular: popular, latest: latest, search: search,
      details: details, chapters: chapters, pages: pages, chapterUrl: chapterUrl,
    };
  }

  // ---- "Toon" Astro-SSR platform factory (hivetoons / vortexscans) --------
  // config: { base, api, id, name, lang?, perPage?, versionCode?, supportsLatest? }
  // Listings come from the JSON query API; the chapter list is read out of an
  // Astro hydration island because the SSR page renders only a recent window.
  // NOTE: this platform's stripTags collapses tags to a SPACE (not ''), so it
  // keeps its own local copy rather than the shared mh.stripTags.
  function Toon(config) {
    var BASE = config.base;
    var API = config.api;
    var NAME = config.name;
    var PER_PAGE = config.perPage || 18;

    function stripTags(s) {
      return s ? s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() : s;
    }
    function abs(url) {
      if (!url) return url;
      if (url.indexOf('//') === 0) return 'https:' + url;
      if (url.indexOf('http') === 0) return url;
      if (url.charAt(0) === '/') return BASE + url;
      return BASE + '/' + url;
    }
    function getHtml(url) {
      return http.get(url, { headers: { Referer: BASE + '/' } }).then(function (r) {
        if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
        if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
        return r.body || '';
      });
    }
    function getJson(url) {
      return getHtml(url).then(function (body) {
        try { return JSON.parse(body); }
        catch (e) { throw new Error('bad JSON from ' + url + ': ' + e); }
      });
    }
    function meta(html, sel, prop) {
      var m = new RegExp('<meta[^>]+' + sel + '="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
      if (m) return m[1];
      m = new RegExp('<meta[^>]+content="([^"]*)"[^>]+' + sel + '="' + prop + '"', 'i').exec(html);
      return m ? m[1] : null;
    }

    function listing(params, page) {
      var url = API + '?perPage=' + PER_PAGE + '&page=' + page + params;
      return getJson(url).then(function (data) {
        var posts = (data && data.posts) || [];
        var mangas = [];
        for (var i = 0; i < posts.length; i++) {
          var p = posts[i];
          if (!p || !p.slug) continue;
          mangas.push({
            url: BASE + '/series/' + p.slug,
            title: p.postTitle || p.slug,
            thumbnail_url: p.featuredImage || null,
          });
        }
        var total = data && data.totalCount;
        var hasNext = typeof total === 'number'
          ? page * PER_PAGE < total
          : mangas.length >= PER_PAGE;
        return { mangas: mangas, has_next_page: hasNext };
      });
    }
    function popular(page) { return listing('&orderBy=totalViews', page); }
    function latest(page) { return listing('&orderBy=updatedAt', page); }
    function search(query, page) {
      return listing('&searchTerm=' + encodeURIComponent(query || ''), page);
    }

    function mapStatus(s) {
      s = (s || '').toLowerCase();
      if (s.indexOf('ongoing') >= 0) return 1;
      if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
      if (s.indexOf('hiatus') >= 0 || s.indexOf('paused') >= 0) return 6;
      if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
      return 0;
    }
    function details(manga) {
      return getHtml(abs(manga.url)).then(function (html) {
        var h1 = /<h1[^>]*>([^<]+)<\/h1>/.exec(html);
        var title = h1 ? stripTags(h1[1]) : (manga.title || '');

        var description = meta(html, 'name', 'description') ||
          meta(html, 'property', 'og:description');
        if (description) description = decode(stripTags(description));

        var status = 0;
        var stM = /Status<\/h1>[\s\S]{0,300}?>\s*(ONGOING|COMPLETED|FINISHED|HIATUS|PAUSED|DROPPED|CANCEL\w*)\s*</i.exec(html);
        if (stM) status = mapStatus(stM[1]);

        // Genres are serialized in an astro-island's entity-escaped props JSON:
        //   genres&quot;:[1,[[0,{…name&quot;:[0,&quot;Drama&quot;]…
        var genres = [];
        var gBlock = /genres&quot;:\[1,\[([\s\S]{0,3000}?)\]\]/.exec(html);
        if (gBlock) {
          var gre = /name&quot;:\[0,&quot;([^&]+)&quot;/g, gm;
          while ((gm = gre.exec(gBlock[1])) !== null) {
            if (genres.indexOf(gm[1]) < 0) genres.push(gm[1]);
          }
        }

        var cover = meta(html, 'property', 'og:image');

        return {
          url: manga.url,
          title: decode(title || ''),
          author: null,
          artist: null,
          description: description,
          genre: genres.length ? genres.join(', ') : null,
          status: status,
          thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
          initialized: true,
        };
      });
    }

    // Astro escapes island props as an HTML attribute and wraps every value in
    // a [type,value] pair ([0,x]=value, [1,[…]]=array); undo both.
    function unescapeEntities(s) {
      return s.replace(/&(#x[0-9a-f]+|#\d+|quot|amp|lt|gt|apos|#39);/gi, function (e) {
        var l = e.toLowerCase();
        if (l === '&quot;') return '"';
        if (l === '&amp;') return '&';
        if (l === '&lt;') return '<';
        if (l === '&gt;') return '>';
        if (l === '&apos;' || l === '&#39;') return "'";
        var m = /^&#x([0-9a-f]+);$/i.exec(e);
        if (m) return String.fromCharCode(parseInt(m[1], 16));
        m = /^&#(\d+);$/.exec(e);
        if (m) return String.fromCharCode(parseInt(m[1], 10));
        return e;
      });
    }
    function undoAstro(v) {
      if (v instanceof Array) {
        if (v.length === 2 && (v[0] === 0 || v[0] === 1)) {
          if (v[0] === 0) return undoAstro(v[1]);
          var arr = v[1], a = [];
          for (var i = 0; i < arr.length; i++) a.push(undoAstro(arr[i]));
          return a;
        }
        var b = [];
        for (var j = 0; j < v.length; j++) b.push(undoAstro(v[j]));
        return b;
      }
      if (v && typeof v === 'object') {
        var o = {};
        for (var k in v) if (Object.prototype.hasOwnProperty.call(v, k)) o[k] = undoAstro(v[k]);
        return o;
      }
      return v;
    }
    function chapterIsland(html) {
      var re = /<astro-island\b[^>]*\bprops="([^"]*)"/g, m;
      while ((m = re.exec(html)) !== null) {
        if (m[1].indexOf('initialChap') < 0) continue;
        try {
          var data = undoAstro(JSON.parse(unescapeEntities(m[1])));
          if (data && data.initialChap && data.initialChap.length) return data.initialChap;
        } catch (e) { /* try the next island */ }
      }
      return null;
    }
    function chapters(manga) {
      var slug = (/\/series\/([^\/?#]+)/.exec(manga.url) || [])[1];
      if (!slug) throw new Error('cannot derive series slug from ' + manga.url);
      return getHtml(abs(manga.url)).then(function (html) {
        var list = chapterIsland(html);
        if (!list) throw new Error('chapter list island not found on ' + manga.url);
        var out = [];
        var seenSlug = {};
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          if (!c || !c.slug || seenSlug[c.slug]) continue;
          seenSlug[c.slug] = true;
          // Coin-/time-locked (timed paywall) chapters can't be read — skip.
          if (c.isAccessible === false) continue;
          var num = typeof c.number === 'number' ? c.number : parseFloat(c.number);
          var name = 'Chapter ' + (isNaN(num) ? c.slug.replace(/^chapter-/, '') : num);
          if (c.title) name += ': ' + decode(String(c.title));
          var d = c.createdAt ? Date.parse(c.createdAt) : NaN;
          out.push({
            url: BASE + '/series/' + slug + '/' + c.slug,
            name: decode(name),
            date_upload: isNaN(d) ? 0 : d,
            chapter_number: isNaN(num) ? -1 : num,
          });
        }
        out.sort(function (a, b) { return b.chapter_number - a.chapter_number; });
        return out;
      });
    }

    function pages(chapter) {
      return getHtml(abs(chapter.url)).then(function (html) {
        var out = [];
        var seen = {};
        var idx = 0;
        var re = /<img\b([^>]*)>/g, m;
        while ((m = re.exec(html)) !== null) {
          var src = attr(m[1], 'data-src') || attr(m[1], 'src');
          if (!src) continue;
          src = src.replace(/^\s+|\s+$/g, '');
          if (src.indexOf('//') === 0) src = 'https:' + src;
          if (src.indexOf('http') !== 0) continue;
          // Page images live under …/upload/series/<slug>/…; series covers use
          // /upload/series/featured/ and chapter thumbs /upload/chapter/.
          if (src.indexOf('/upload/series/') < 0) continue;
          if (src.indexOf('/featured/') >= 0) continue;
          if (seen[src]) continue; seen[src] = true;
          out.push({ index: idx++, url: src, image_url: src, headers: { Referer: BASE + '/', 'User-Agent': UA } });
        }
        if (!out.length && /Unlock this chapter|isLockedByCoins&quot;:\[0,true\]/.test(html)) {
          throw new Error('Chapter is coin-locked on ' + NAME);
        }
        return out;
      });
    }
    function chapterUrl(chapter) { return abs(chapter.url); }

    return {
      manifest: {
        id: config.id, name: NAME, lang: config.lang || 'en',
        base_url: BASE,
        version_code: config.versionCode || 1,
        supports_latest: config.supportsLatest !== false,
      },
      popular: popular, latest: latest, search: search,
      details: details, chapters: chapters, pages: pages, chapterUrl: chapterUrl,
    };
  }

  return { attr: attr, pickCover: pickCover, decode: decode, stripTags: stripTags,
           themes: { Madara: Madara, MangaThemesia: MangaThemesia, Toon: Toon } };
})();
''';
