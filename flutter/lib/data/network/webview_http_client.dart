import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'network_preferences.dart';
import 'webview_cookie_sync.dart' show registrableDomain;

/// Routes an HTTP request through an offscreen WebView so it carries a real
/// Chromium TLS/JA3 + header fingerprint.
///
/// Why this exists: some Cloudflare configurations validate the *request
/// fingerprint*, not just the `cf_clearance` cookie. On such sites the Dio
/// client is served the "Just a moment" challenge (HTTP 403/503) even with a
/// valid, freshly-solved clearance, because `dart:io`'s TLS handshake doesn't
/// look like a browser. Copying the cookie can't fix that — the request itself
/// has to originate from the browser engine. (Mihon's OkHttp happens to pass
/// because its Conscrypt TLS is browser-enough; `dart:io`'s isn't.)
///
/// How it works: a single hidden WebView (mounted 1×1 by [OffscreenWebViewHost]
/// in the app root) parks on the target origin — passing Cloudflare via the
/// auto JS challenge or a clearance already in the shared cookie store — then
/// runs an in-page `fetch()` to retrieve the raw response with the page's
/// origin, cookies and fingerprint. The async result comes back over a JS
/// channel. Requests are serialised (one WebView).
///
/// Android-only for now; iOS WKWebView support is a TODO (returns null so the
/// caller keeps the Dio result).
class WebViewHttpClient {
  WebViewHttpClient._();

  static final WebViewHttpClient instance = WebViewHttpClient._();

  /// Headers a browser forbids scripts from setting on `fetch()` — leaving
  /// them in would be silently dropped at best, so strip them. The WebView's
  /// own UA / automatic Referer / cookie handling covers these anyway.
  static const _forbiddenHeaders = {
    'user-agent', 'referer', 'cookie', 'host', 'origin', 'accept-encoding',
    'connection', 'content-length',
  };

  WebViewController? _controller;
  final Completer<void> _ready = Completer<void>();

  /// Flipped true the first time a Cloudflare-challenged request actually needs
  /// the browser. [OffscreenWebViewHost] watches it and only then creates the
  /// WebView — most sessions never touch a fingerprint-walled source and
  /// shouldn't pay the cost of an always-on Chromium instance at startup.
  final ValueNotifier<bool> activate = ValueNotifier<bool>(false);

  /// Set once we've waited for a controller that never arrived (e.g. the
  /// headless WorkManager isolate, where no [OffscreenWebViewHost] is mounted).
  /// Stops every subsequent request from eating the attach grace period. Reset
  /// if a controller does later attach.
  bool _giveUp = false;

  /// `scheme://host` the WebView is currently parked on AND confirmed past
  /// Cloudflare; we only re-navigate when the origin changes. Left null after a
  /// failed warm-up so the next request retries it.
  String? _origin;

  /// One WebView ⇒ one in-flight request at a time.
  Future<void> _lock = Future<void>.value();

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 0;

  /// Whether the WebView path is usable on this platform. Note this only gates
  /// the platform; [request] additionally bails when no controller is attached
  /// (e.g. background isolate) so it never stalls or pretends to work there.
  bool get isAvailable => Platform.isAndroid;

  /// Builds the controller the [OffscreenWebViewHost] mounts. Centralised so
  /// the JS result channel, UA and ad-redirect nav-blocking live in one place.
  WebViewController buildController() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(defaultUserAgent)
      ..addJavaScriptChannel('CFFetch', onMessageReceived: _onFetchResult)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme != 'http' && uri.scheme != 'https') {
              return NavigationDecision.prevent; // intent:/market: ad redirects
            }
            final base = _origin == null ? null : Uri.tryParse(_origin!)?.host;
            if (base != null && !_sameSite(uri.host, base)) {
              return NavigationDecision.prevent; // cross-site ad redirect
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    _controller = c;
    _giveUp = false; // a controller exists now; allow requests again
    if (!_ready.isCompleted) _ready.complete();
    return c;
  }

  void _onFetchResult(JavaScriptMessage message) {
    try {
      final m = jsonDecode(message.message) as Map<String, dynamic>;
      final id = (m['id'] as num).toInt();
      _pending.remove(id)?.complete(m);
    } catch (_) {
      // Malformed payload — let the request time out.
    }
  }

  bool _sameSite(String host, String base) =>
      registrableDomain(host) == registrableDomain(base);

  /// Fetches [url] through the browser. Returns the same shape the Dio path
  /// produces (`ok/status/body/headers/final_url`), or null when the WebView
  /// path is unavailable or fails — so the caller falls back to the Dio result.
  Future<Map<String, dynamic>?> request(
    String url, {
    String method = 'GET',
    Map<String, dynamic>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 40),
  }) {
    if (!isAvailable || _giveUp) return Future.value(null);
    // Ask the host to create the WebView now (no-op if already up / on an
    // isolate without a host). _run then waits briefly for it to attach.
    activate.value = true;
    final completer = Completer<Map<String, dynamic>?>();
    // Serialise: chain onto the lock so only one fetch runs at a time. An outer
    // timeout guarantees the lock always advances even if a platform call
    // (loadRequest/runJavaScript) hangs — otherwise one stuck navigation would
    // wedge every subsequent request for the app's lifetime.
    _lock = _lock.then((_) async {
      try {
        final res = await _run(url, method, headers, body, timeout)
            .timeout(timeout + const Duration(seconds: 10), onTimeout: () => null);
        completer.complete(res);
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>?> _run(
    String url,
    String method,
    Map<String, dynamic>? headers,
    Object? body,
    Duration timeout,
  ) async {
    // Wait briefly for the offscreen host to attach its controller. If it never
    // does (headless background isolate), give up so later requests bail fast
    // instead of each stalling for the grace period.
    if (_controller == null) {
      await _ready.future
          .timeout(const Duration(seconds: 6), onTimeout: () {});
      if (_controller == null) {
        _giveUp = true;
        return null;
      }
    }
    final controller = _controller!;

    final target = Uri.tryParse(url);
    if (target == null) return null;
    final origin = '${target.scheme}://${target.host}';
    if (_origin != origin) {
      if (!await _warmUp(controller, origin, timeout)) return null;
      _origin = origin; // only commit once confirmed past the interstitial
    }

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      await controller
          .runJavaScript(_buildFetchJs(id, url, method, headers, body))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      _pending.remove(id); // never executed → don't leak the completer
      return null;
    }

    final result = await completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        return const {'__timeout': true};
      },
    );
    if (result['__timeout'] == true || result['ok'] != true) return null;
    final status = (result['status'] as num?)?.toInt() ?? 200;
    final bodyStr = result['body']?.toString() ?? '';
    // The WebView may still have hit a challenge (e.g. interactive Turnstile it
    // can't auto-pass offscreen). Don't hand a challenge page back as content —
    // fall through to the Dio result instead.
    if (_isChallenge(status, bodyStr)) return null;
    return {
      'ok': true,
      'status': status,
      'body': bodyStr,
      'headers': const <String, String>{},
      'final_url': result['url']?.toString() ?? url,
      'via': 'webview',
    };
  }

  static bool _isChallenge(int status, String body) {
    if (status != 403 && status != 503 && status != 429) return false;
    return body.contains('Just a moment') ||
        body.contains('challenge-platform') ||
        body.contains('challenge-error') ||
        body.contains('cf-challenge') ||
        body.contains('_cf_chl_opt');
  }

  /// Parks the WebView on [origin] and waits until it's past any Cloudflare
  /// interstitial (so a subsequent same-origin fetch isn't itself challenged).
  /// Returns false if it never cleared within [timeout].
  Future<bool> _warmUp(
      WebViewController c, String origin, Duration timeout) async {
    try {
      await c.loadRequest(Uri.parse(origin)).timeout(const Duration(seconds: 15));
    } catch (_) {
      return false;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        final r = await c
            .runJavaScriptReturningResult(
              "(function(){var t=(document.title||'').toLowerCase();"
              "return (document.readyState==='complete'"
              "&&t.indexOf('just a moment')<0&&t.indexOf('verifying')<0"
              "&&t.indexOf('attention required')<0)?'1':'0';})()",
            )
            .timeout(const Duration(seconds: 5));
        if (r.toString().trim().replaceAll('"', '') == '1') return true;
      } catch (_) {
        // Keep polling until the deadline.
      }
    }
    return false;
  }

  String _buildFetchJs(
    int id,
    String url,
    String method,
    Map<String, dynamic>? headers,
    Object? body,
  ) {
    final clean = <String, String>{};
    headers?.forEach((k, v) {
      if (!_forbiddenHeaders.contains(k.toLowerCase())) {
        clean[k] = v.toString();
      }
    });
    final hasBody = body != null && method != 'GET' && method != 'HEAD';
    final bodyLiteral =
        hasBody ? jsonEncode(body is String ? body : jsonEncode(body)) : null;
    return '''
(function(){
  var opts = { method: ${jsonEncode(method)}, headers: ${jsonEncode(clean)}, credentials: 'include' };
  ${hasBody ? 'opts.body = $bodyLiteral;' : ''}
  fetch(${jsonEncode(url)}, opts).then(function(r){
    return r.text().then(function(t){
      CFFetch.postMessage(JSON.stringify({id: $id, ok: true, status: r.status, body: t, url: r.url}));
    });
  }).catch(function(e){
    CFFetch.postMessage(JSON.stringify({id: $id, ok: false, error: String(e)}));
  });
})();
''';
  }
}

/// Mounts the shared offscreen WebView (1×1, covered by the app) so
/// [WebViewHttpClient]'s controller is alive and runs page JS. Place once near
/// the app root (e.g. via `MaterialApp.builder`).
class OffscreenWebViewHost extends StatefulWidget {
  const OffscreenWebViewHost({super.key});

  @override
  State<OffscreenWebViewHost> createState() => _OffscreenWebViewHostState();
}

class _OffscreenWebViewHostState extends State<OffscreenWebViewHost> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final client = WebViewHttpClient.instance;
    if (!client.isAvailable) return;
    client.activate.addListener(_onActivate);
    if (client.activate.value) _onActivate(); // already requested before mount
  }

  void _onActivate() {
    if (_controller != null || !mounted) return;
    // Create the WebView lazily on first need (see [WebViewHttpClient.activate]).
    setState(() => _controller = WebViewHttpClient.instance.buildController());
  }

  @override
  void dispose() {
    WebViewHttpClient.instance.activate.removeListener(_onActivate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    // 1×1 and parked under the app — laid out (so the platform view runs page
    // JS) but visually imperceptible.
    return SizedBox(width: 1, height: 1, child: WebViewWidget(controller: c));
  }
}
