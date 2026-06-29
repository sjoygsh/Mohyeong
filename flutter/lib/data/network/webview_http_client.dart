import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'network_preferences.dart';
import 'webview_cookie_sync.dart' show registrableDomain;

/// Fetches a URL by driving an offscreen WebView so the request carries a real
/// Chromium TLS/JA3 + header fingerprint.
///
/// Why this exists: some Cloudflare configurations validate the *request
/// fingerprint*, not just the `cf_clearance` cookie. On such sites the Dio
/// client is served the "Just a moment" challenge (HTTP 403/503) even with a
/// valid, freshly-solved clearance, because `dart:io`'s TLS handshake doesn't
/// look like a browser. Copying the cookie can't fix that — the request itself
/// has to originate from the browser engine.
///
/// How it works: a single hidden 1×1 WebView (mounted by [OffscreenWebViewHost]
/// in the app root, created lazily on first need) NAVIGATES to the target URL.
/// A top-level navigation passes Cloudflare's managed challenge (the WebView
/// runs the challenge JS and auto-redirects to the real page) — unlike an
/// in-page `fetch()`/XHR, which Cloudflare serves the challenge to because of
/// its `Sec-Fetch-Mode: cors`. Once the real page is up we read the document:
/// `outerHTML` for HTML, `body.innerText` for JSON/text endpoints (Chrome wraps
/// a JSON response in `<pre>`), which is exactly what the Dio path returns as
/// the response body. Requests are serialised (one WebView).
///
/// GET only — the auto-retry in the http bridge is gated to idempotent methods,
/// and a navigation can't carry a request body anyway. Android-only for now;
/// elsewhere [isAvailable] is false and callers keep the Dio result.
class WebViewHttpClient {
  WebViewHttpClient._();

  static final WebViewHttpClient instance = WebViewHttpClient._();

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

  /// Origin host the WebView is currently navigating, used by the nav delegate
  /// to block cross-site ad redirects while allowing the site's own
  /// (Cloudflare ↔ real page) navigation.
  String? _navHost;

  /// `scheme://host` the WebView is currently parked on (set after a successful
  /// navigation). Lets cover fetches skip re-navigation when the WebView is
  /// already on the cover's origin (e.g. right after the listing fetch).
  String? _currentOrigin;

  /// One WebView ⇒ one in-flight navigation at a time.
  Future<void> _lock = Future<void>.value();

  /// In-page image-fetch results, keyed by request id (the JS canvas extract
  /// posts back over the CFImg channel since toDataURL is async).
  final Map<int, Completer<Map<String, dynamic>>> _imgPending = {};
  int _imgId = 0;

  /// Small cache of WebView-fetched cover bytes (covers are tiny) so repeated
  /// rebuilds / scroll recycling don't re-extract the same image.
  final Map<String, Uint8List> _imgCache = {};

  /// Negative cache (url -> expiry epoch ms): a cover that failed isn't retried
  /// for a while, so a broken tile recycling into view doesn't re-drive the
  /// (serialised) WebView nav+draw every time. Success-only [_imgCache] alone
  /// would let failures loop forever.
  final Map<String, int> _imgFailed = {};

  /// In-flight cover requests, so concurrent identical URLs (a grid + its
  /// scroll-recycled tiles) share one fetch instead of queuing duplicates.
  final Map<String, Future<Uint8List?>> _imgInflight = {};

  /// Whether the WebView path is usable on this platform. [request]
  /// additionally bails when no controller is attached (background isolate).
  bool get isAvailable => Platform.isAndroid;

  /// Builds the controller the [OffscreenWebViewHost] mounts. Centralised so
  /// the UA and ad-redirect nav-blocking live in one place.
  WebViewController buildController() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(defaultUserAgent)
      ..addJavaScriptChannel('CFImg', onMessageReceived: _onImg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme != 'http' && uri.scheme != 'https') {
              return NavigationDecision.prevent; // intent:/market: ad redirects
            }
            final base = _navHost;
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
    Duration settle = const Duration(milliseconds: 1800),
    String? readyJs,
  }) {
    if (!isAvailable || _giveUp) return Future.value(null);
    // Ask the host to create the WebView now (no-op if already up / on an
    // isolate without a host). _run then waits briefly for it to attach.
    activate.value = true;
    final completer = Completer<Map<String, dynamic>?>();
    // Serialise + outer timeout so a stuck platform call can't wedge the queue.
    _lock = _lock.then((_) async {
      try {
        final res = await _run(url, timeout, settle, readyJs)
            .timeout(timeout + const Duration(seconds: 10), onTimeout: () => null);
        completer.complete(res);
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>?> _run(
      String url, Duration timeout, Duration settle, [String? readyJs]) async {
    if (_controller == null) {
      await _ready.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      if (_controller == null) {
        _giveUp = true;
        return null;
      }
    }
    final controller = _controller!;

    final target = Uri.tryParse(url);
    if (target == null) return null;
    _navHost = target.host;

    if (!await _navigate(controller, url, timeout, settle, readyJs)) return null;
    _currentOrigin = '${target.scheme}://${target.host}';

    String raw;
    try {
      raw = (await controller
              .runJavaScriptReturningResult(
                "(function(){try{var ct=(document.contentType||'').toLowerCase();"
                "if(ct.indexOf('json')>=0||ct.indexOf('text/plain')>=0){"
                "return document.body?document.body.innerText:'';}"
                "return document.documentElement.outerHTML;}catch(e){return '';}})()",
              )
              .timeout(const Duration(seconds: 10)))
          .toString();
    } catch (_) {
      return null;
    }
    final bodyStr = _decodeJsString(raw);
    if (bodyStr.isEmpty || _isChallengeBody(bodyStr)) return null;
    return {
      'ok': true,
      'status': 200,
      'body': bodyStr,
      'headers': const <String, String>{},
      'final_url': url,
      'via': 'webview',
    };
  }

  void _onImg(JavaScriptMessage message) {
    try {
      final m = jsonDecode(message.message) as Map<String, dynamic>;
      final id = (m['id'] as num).toInt();
      _imgPending.remove(id)?.complete(m);
    } catch (_) {
      // Malformed → the request times out.
    }
  }

  /// Fetches a cover/image's bytes through the browser, for sources whose CDN
  /// 403s non-browser clients (cached_network_image can't pass the fingerprint
  /// wall). Parks the WebView on the image's own origin (so the in-page <img>
  /// is same-origin and the canvas isn't tainted, and Cloudflare is passed by
  /// the browser fingerprint), then draws it to a canvas and reads the bytes.
  /// Returns null when unavailable/failed so the caller shows its error box.
  Future<Uint8List?> fetchImageBytes(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (!isAvailable || _giveUp) return Future.value(null);
    final cached = _imgCache[url];
    if (cached != null) return Future.value(cached);
    final failedUntil = _imgFailed[url];
    if (failedUntil != null) {
      if (DateTime.now().millisecondsSinceEpoch < failedUntil) {
        return Future.value(null); // negative-cached; don't re-drive the WebView
      }
      _imgFailed.remove(url);
    }
    final inflight = _imgInflight[url];
    if (inflight != null) return inflight; // share one fetch for duplicate URLs
    activate.value = true;
    final completer = Completer<Uint8List?>();
    _imgInflight[url] = completer.future;
    _lock = _lock.then((_) async {
      try {
        final bytes = await _runImg(url, timeout)
            .timeout(timeout + const Duration(seconds: 10), onTimeout: () => null);
        if (bytes == null) _noteImgFailure(url);
        completer.complete(bytes);
      } catch (_) {
        _noteImgFailure(url);
        completer.complete(null);
      } finally {
        _imgInflight.remove(url);
      }
    });
    return completer.future;
  }

  /// Record a failed cover so it isn't re-fetched for 2 minutes (bounded).
  void _noteImgFailure(String url) {
    _imgFailed[url] = DateTime.now().millisecondsSinceEpoch + 120000;
    if (_imgFailed.length > 256) _imgFailed.remove(_imgFailed.keys.first);
  }

  Future<Uint8List?> _runImg(String url, Duration timeout) async {
    if (_controller == null) {
      await _ready.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      if (_controller == null) {
        _giveUp = true;
        return null;
      }
    }
    final controller = _controller!;
    final target = Uri.tryParse(url);
    if (target == null) return null;
    final origin = '${target.scheme}://${target.host}';
    if (_currentOrigin != origin) {
      _navHost = target.host;
      if (!await _navigate(controller, origin, timeout)) return null;
      _currentOrigin = origin;
    }

    final id = _imgId++;
    final completer = Completer<Map<String, dynamic>>();
    _imgPending[id] = completer;
    try {
      await controller.runJavaScript(_buildImgJs(id, url))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      _imgPending.remove(id);
      return null;
    }
    final res = await completer.future.timeout(timeout, onTimeout: () {
      _imgPending.remove(id);
      return const {'__timeout': true};
    });
    if (res['__timeout'] == true || res['ok'] != true) return null;
    final data = res['data']?.toString() ?? '';
    final comma = data.indexOf(',');
    if (comma < 0) return null;
    try {
      final bytes = base64Decode(data.substring(comma + 1));
      if (bytes.isNotEmpty && bytes.length <= 4 * 1024 * 1024) {
        _imgCache[url] = bytes;
        if (_imgCache.length > 256) _imgCache.remove(_imgCache.keys.first);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String _buildImgJs(int id, String url) {
    return '''
(function(){
  var im = new Image();
  im.onload = function(){
    try{
      // Downscale to a grid-cover size before encoding: a full-res cover would
      // base64 to hundreds of KB over the channel and decode full-size in Flutter.
      var MAX = 480;
      var w = im.naturalWidth || MAX, h = im.naturalHeight || MAX;
      var s = Math.min(1, MAX / Math.max(w, h));
      var c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(w * s)); c.height = Math.max(1, Math.round(h * s));
      c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
      CFImg.postMessage(JSON.stringify({id:$id, ok:true, data:c.toDataURL('image/jpeg',0.85)}));
    }catch(e){ CFImg.postMessage(JSON.stringify({id:$id, ok:false, error:String(e)})); }
  };
  im.onerror = function(){ CFImg.postMessage(JSON.stringify({id:$id, ok:false, error:'load'})); };
  im.src = ${jsonEncode(url)};
})();
''';
  }

  /// Navigates to [url] and waits until the WebView is past any Cloudflare
  /// interstitial and the real page has rendered. Returns false on timeout.
  Future<bool> _navigate(WebViewController c, String url, Duration timeout,
      [Duration settle = const Duration(milliseconds: 1800), String? readyJs]) async {
    try {
      await c.loadRequest(Uri.parse(url)).timeout(const Duration(seconds: 15));
    } catch (_) {
      return false;
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        final r = (await c
                .runJavaScriptReturningResult(
                  "(function(){var t=(document.title||'').toLowerCase();"
                  "return (document.readyState==='complete'"
                  "&&t.indexOf('just a moment')<0&&t.indexOf('verifying')<0"
                  "&&t.indexOf('attention required')<0)?'1':'0';})()",
                )
                .timeout(const Duration(seconds: 5)))
            .toString();
        if (r.replaceAll('"', '').trim() == '1') {
          // Past Cloudflare + base document ready. Rather than sleep a flat
          // [settle], wait only as long as content actually needs: poll a
          // caller-supplied readiness predicate ([readyJs], e.g. chapter rows
          // present) or fall back to DOM-size stabilisation. [settle] is the
          // CEILING, not a fixed floor — most pages settle in a few hundred ms,
          // so this replaces the old unconditional 1.8s / 8s waits.
          await _awaitContent(c, settle, readyJs);
          return true;
        }
      } catch (_) {
        // Keep polling until the deadline.
      }
    }
    return false;
  }

  /// Waits for async/lazy content to finish populating, capped at [ceiling].
  /// With [readyJs] (a JS boolean expression) it returns as soon as that's
  /// true; otherwise it returns once the DOM node count stops growing (two
  /// equal samples ~250ms apart). A short minimum lets a static page flush.
  Future<void> _awaitContent(
      WebViewController c, Duration ceiling, String? readyJs) async {
    final deadline = DateTime.now().add(ceiling);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var lastCount = -1;
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (readyJs != null) {
          final r = (await c
                  .runJavaScriptReturningResult(
                    '(function(){try{return ($readyJs)?1:0;}catch(e){return 0;}})()',
                  )
                  .timeout(const Duration(seconds: 5)))
              .toString();
          if (r.replaceAll('"', '').trim() == '1') return;
        } else {
          final r = (await c
                  .runJavaScriptReturningResult(
                    "document.getElementsByTagName('*').length",
                  )
                  .timeout(const Duration(seconds: 5)))
              .toString();
          final n = int.tryParse(r.replaceAll('"', '').trim()) ?? -1;
          if (n >= 0 && n == lastCount) return; // unchanged → settled
          lastCount = n;
        }
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// `runJavaScriptReturningResult` returns a JSON-encoded string on Android
  /// (quoted + escaped); decode it back to the real HTML/JSON text.
  static String _decodeJsString(String s) {
    if (s.startsWith('"')) {
      try {
        return jsonDecode(s) as String;
      } catch (_) {/* leave as-is */}
    }
    return s;
  }

  static bool _isChallengeBody(String body) =>
      body.contains('Just a moment') ||
      body.contains('challenge-platform') ||
      body.contains('challenge-error') ||
      body.contains('_cf_chl_opt');
}

/// Mounts the shared hidden WebView so [WebViewHttpClient]'s controller is
/// alive and runs page JS. Created lazily on first need (see
/// [WebViewHttpClient.activate]).
///
/// It is rendered at FULL SIZE but parked behind the (opaque, full-screen) app
/// in the [Stack] — a 1×1 viewport gets flagged by Cloudflare's challenge
/// (which inspects window dimensions/visibility) and never auto-solves, whereas
/// a real-sized viewport behind the UI passes while staying invisible to the
/// user. [IgnorePointer] keeps it from ever intercepting touches.
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
    // Full size (real viewport so Cloudflare's challenge runs) but behind the
    // opaque app and non-interactive.
    return IgnorePointer(child: WebViewWidget(controller: c));
  }
}
