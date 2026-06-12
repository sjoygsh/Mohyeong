import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

/// Owns a single JavaScript runtime (one per extension instance) and bridges
/// the host APIs the JS code calls into:
///
///   * `http.get(url, opts)` / `http.post(url, opts)` — returns a Promise of
///     `{ status, body, headers }`.
///   * `console.log/warn/error` — forwarded to Dart via [onLog].
///
/// The contract on the JS side is documented in `assets/extension_api.js`
/// (the small preamble loaded before every extension). Extensions register
/// themselves by assigning to the global `__extension` after definition.
class JsRuntime {
  JsRuntime({required this.dio, this.onLog}) {
    _runtime = getJavascriptRuntime();
    _setup();
  }

  late final JavascriptRuntime _runtime;
  final Dio dio;
  final void Function(String level, String message)? onLog;

  void _setup() {
    _runtime.enableHandlePromises();

    // HTTP bridge. The JS side awaits sendMessage('http', ...) and gets back
    // the response body. Errors are surfaced as { ok: false, error: '...' }.
    _runtime.onMessage('http', (dynamic args) async {
      try {
        final Map<String, dynamic> req = args is String
            ? jsonDecode(args) as Map<String, dynamic>
            : Map<String, dynamic>.from(args as Map);
        final method = (req['method'] as String? ?? 'GET').toUpperCase();
        final url = req['url'] as String;
        final headers = (req['headers'] as Map?)?.cast<String, dynamic>();
        final body = req['body'];
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
        return {
          'ok': true,
          'status': response.statusCode,
          'body': response.data?.toString() ?? '',
          'headers': response.headers.map.map(
            (k, v) => MapEntry(k, v.join(', ')),
          ),
          'final_url': response.realUri.toString(),
        };
      } catch (e) {
        return {'ok': false, 'error': e.toString()};
      }
    });

    // Console bridge.
    _runtime.onMessage('log', (dynamic args) {
      final Map m = args is String
          ? (jsonDecode(args) as Map)
          : (args as Map);
      onLog?.call(m['level'] as String? ?? 'log', m['message'] as String? ?? '');
      return null;
    });

    // Preamble: defines the `http`, `console`, and `__expose` globals every
    // extension expects. Must be evaluated before the extension source.
    _runtime.evaluate(_preamble);
  }

  /// Loads the extension source. After this returns, the JS side must have
  /// populated `__extension` with the manifest + method table.
  Future<void> loadExtensionSource(String source) async {
    final result = _runtime.evaluate(source);
    if (result.isError) {
      throw JsRuntimeException('extension load failed: ${result.stringResult}');
    }
  }

  /// Reads the manifest the extension registered into `__extension.manifest`.
  Map<String, dynamic> readManifest() {
    final json = _runtime.evaluate(
      'JSON.stringify(__extension && __extension.manifest || null)',
    );
    if (json.isError) {
      throw JsRuntimeException('manifest read failed: ${json.stringResult}');
    }
    final str = json.stringResult;
    if (str == 'null' || str.isEmpty) {
      throw JsRuntimeException(
        'extension did not register __extension.manifest',
      );
    }
    return jsonDecode(str) as Map<String, dynamic>;
  }

  /// Pushes the user's per-source settings into the runtime as the
  /// `__sourcePrefs` global (values are all strings). Called after load and
  /// whenever the user changes a setting, so extensions see updates without
  /// a reload.
  void setSourcePrefs(Map<String, String> prefs) {
    _runtime.evaluate('__sourcePrefs = ${jsonEncode(prefs)};');
  }

  /// Whether the extension defines [method] — used for optional contract
  /// methods (e.g. `chapterUrl`) where absence falls back to a Dart default.
  bool hasMethod(String method) {
    final result = _runtime.evaluate(
      'String(__extension && typeof __extension.$method === "function")',
    );
    return !result.isError && result.stringResult == 'true';
  }

  /// Invokes a method on `__extension` and returns the parsed JSON result.
  /// Arguments are serialised via JSON.stringify, so they must be JSON-safe.
  Future<dynamic> invoke(String method, List<dynamic> args) async {
    final argsJson = jsonEncode(args);
    final call =
        '(async()=>{const r=await __extension.$method(...$argsJson);return JSON.stringify(r);})()';
    final promiseResult = await _runtime.evaluateAsync(call);
    final resolved = await _runtime.handlePromise(promiseResult);
    if (resolved.isError) {
      throw JsRuntimeException(
        'extension.$method failed: ${resolved.stringResult}',
      );
    }
    final str = resolved.stringResult;
    if (str.isEmpty || str == 'undefined') return null;
    return jsonDecode(str);
  }

  void dispose() {
    _runtime.dispose();
  }
}

class JsRuntimeException implements Exception {
  JsRuntimeException(this.message);
  final String message;
  @override
  String toString() => 'JsRuntimeException: $message';
}

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
