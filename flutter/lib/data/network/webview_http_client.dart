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
/// How it works: a single hidden WebView (mounted by [OffscreenWebViewHost]
/// in the app root, created lazily on first need and torn down again after
/// [_idleTeardown] without requests) NAVIGATES to the target URL.
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
  Completer<void> _ready = Completer<void>();

  /// Flipped true the first time a Cloudflare-challenged request actually needs
  /// the browser. [OffscreenWebViewHost] watches it and only then creates the
  /// WebView — most sessions never touch a fingerprint-walled source and
  /// shouldn't pay the cost of an always-on Chromium instance at startup.
  final ValueNotifier<bool> activate = ValueNotifier<bool>(false);

  /// Set once we've waited for a controller that never arrived (e.g. the
  /// headless WorkManager isolate, where no [OffscreenWebViewHost] is mounted).
  /// Stops every subsequent request from eating the attach grace period.
  ///
  /// A DEADLINE, not a latch. As a permanent flag this could never clear on the
  /// isolate that matters: the bail ran before [activate] was set, the host
  /// only builds a controller when [activate] flips true, and the flag only
  /// resets when a controller is built — so one slow attach silenced the
  /// browser path for the rest of the process. That is not hypothetical on a
  /// cold start: open Browse in the first seconds and the icon probes for every
  /// fingerprint-walled source can lose the 6s race together, then each records
  /// a miss that stands for its full 12-hour TTL. The headless isolate this
  /// guard was written for is still covered — it just re-pays the grace period
  /// once per window instead of once per process.
  DateTime? _attachFailedUntil;
  static const Duration _attachRetryAfter = Duration(seconds: 30);

  bool get _giveUp {
    final until = _attachFailedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _noteAttachFailed() =>
      _attachFailedUntil = DateTime.now().add(_attachRetryAfter);

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

  /// Requests queued or in flight. While zero for [_idleTeardown], the WebView
  /// is torn down: an idle platform view isn't free — every app frame pays a
  /// compositing split for it — and Mihon likewise destroys its challenge
  /// WebView after use rather than keeping one alive. The next request
  /// re-activates a fresh one; the CF clearance cookie lives in the global
  /// CookieManager, so it survives teardown.
  int _pending = 0;
  Timer? _idleTimer;
  static const Duration _idleTeardown = Duration(seconds: 90);

  void _noteBusy() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _pending++;
  }

  void _noteDone() {
    _pending--;
    if (_pending <= 0) {
      _pending = 0;
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleTeardown, _teardownIfIdle);
    }
  }

  void _teardownIfIdle() {
    _idleTimer = null;
    if (_pending > 0) return;
    _controller = null;
    _ready = Completer<void>();
    _navHost = null;
    _currentOrigin = null;
    // The host watches this and unmounts the WebViewWidget; flipping it back
    // to true later mounts a fresh one.
    activate.value = false;
  }

  /// Whether the last navigation's caller-supplied readiness predicate
  /// (`readyJs`) actually fired before the settle ceiling. Single-threaded
  /// under [_lock]. Callers use it to mark a snapshot that MAY be missing
  /// its content (cold WebView burned the window on a challenge) so the
  /// response cache can skip it — a cached not-ready snapshot turns one
  /// slow render into repeated "no content" parses for its whole TTL.
  bool _lastNavReady = true;

  /// In-page image-fetch results, keyed by request id (the JS canvas extract
  /// posts back over the CFImg channel since toDataURL is async).
  final Map<int, Completer<Map<String, dynamic>>> _imgPending = {};
  int _imgId = 0;

  /// Small cache of WebView-fetched image bytes so repeated rebuilds /
  /// scroll recycling don't re-extract the same image. Keyed by
  /// resolution-variant ('c:' cover-sized / 'f:' full-resolution — the same
  /// URL must not satisfy both). Byte-budgeted: full-resolution reader pages
  /// run to megabytes, so a count cap alone could pin hundreds of MB.
  final Map<String, Uint8List> _imgCache = {};
  int _imgCacheBytes = 0;
  static const int _imgCacheMaxEntryBytes = 4 * 1024 * 1024;
  static const int _imgCacheBudgetBytes = 32 * 1024 * 1024;

  void _imgCacheStore(String cacheKey, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _imgCacheMaxEntryBytes) return;
    final prev = _imgCache.remove(cacheKey);
    if (prev != null) _imgCacheBytes -= prev.length;
    _imgCache[cacheKey] = bytes;
    _imgCacheBytes += bytes.length;
    while (_imgCache.length > 256 || _imgCacheBytes > _imgCacheBudgetBytes) {
      final oldest = _imgCache.keys.first;
      _imgCacheBytes -= _imgCache[oldest]!.length;
      _imgCache.remove(oldest);
    }
  }

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
    _attachFailedUntil = null; // a controller exists now; allow requests again
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
    _noteBusy();
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
      } finally {
        _noteDone();
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>?> _run(
      String url, Duration timeout, Duration settle, [String? readyJs]) async {
    if (_controller == null) {
      await _ready.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      if (_controller == null) {
        _noteAttachFailed();
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
      'ready': _lastNavReady,
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
  /// 403s non-browser clients (the plain HTTP image path can't pass the fingerprint
  /// wall). Parks the WebView on the image's own origin (so the in-page fetch
  /// is same-origin and an <img> canvas isn't tainted, and Cloudflare is passed
  /// by the browser fingerprint), then reads the bytes.
  ///
  /// [fullResolution] returns the image's ORIGINAL bytes (in-page `fetch`,
  /// falling back to a natural-size canvas re-encode) — reader pages need
  /// this. When false (covers/thumbnails), the image is downscaled to a
  /// 480px grid-cover size before crossing the JS channel, which is far
  /// cheaper for a scrolling grid but unusable for a full-screen page.
  /// Returns null when unavailable/failed so the caller shows its error box.
  Future<Uint8List?> fetchImageBytes(
    String url, {
    Duration timeout = const Duration(seconds: 30),
    bool fullResolution = false,
  }) {
    if (!isAvailable || _giveUp) return Future.value(null);
    final cacheKey = fullResolution ? 'f:$url' : 'c:$url';
    final cached = _imgCache[cacheKey];
    if (cached != null) return Future.value(cached);
    final failedUntil = _imgFailed[url];
    if (failedUntil != null) {
      if (DateTime.now().millisecondsSinceEpoch < failedUntil) {
        return Future.value(null); // negative-cached; don't re-drive the WebView
      }
      _imgFailed.remove(url);
    }
    final inflight = _imgInflight[cacheKey];
    if (inflight != null) return inflight; // share one fetch for duplicate URLs
    _noteBusy();
    activate.value = true;
    final completer = Completer<Uint8List?>();
    _imgInflight[cacheKey] = completer.future;
    _lock = _lock.then((_) async {
      try {
        final bytes = await _runImg(url, timeout, fullResolution, cacheKey)
            .timeout(timeout + const Duration(seconds: 10), onTimeout: () => null);
        if (bytes == null) _noteImgFailure(url);
        completer.complete(bytes);
      } catch (_) {
        _noteImgFailure(url);
        completer.complete(null);
      } finally {
        _imgInflight.remove(cacheKey);
        _noteDone();
      }
    });
    return completer.future;
  }

  /// Record a failed cover so it isn't re-fetched for 2 minutes (bounded).
  void _noteImgFailure(String url) {
    _imgFailed[url] = DateTime.now().millisecondsSinceEpoch + 120000;
    if (_imgFailed.length > 256) _imgFailed.remove(_imgFailed.keys.first);
  }

  Future<Uint8List?> _runImg(
    String url,
    Duration timeout,
    bool fullResolution,
    String cacheKey,
  ) async {
    if (_controller == null) {
      await _ready.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      if (_controller == null) {
        _noteAttachFailed();
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
      await controller.runJavaScript(_buildImgJs(id, url, fullResolution))
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
      if (bytes.isNotEmpty) _imgCacheStore(cacheKey, bytes);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  String _buildImgJs(int id, String url, bool fullResolution) {
    final u = jsonEncode(url);
    if (fullResolution) {
      // Reader pages: the ORIGINAL bytes, byte-exact — an in-page fetch is
      // same-origin (the WebView is parked on the image's origin), sends the
      // browser TLS/cookies that pass the wall, and skips the lossy canvas
      // re-encode. Falls back to a natural-size canvas (jpeg 0.92) for the
      // rare response fetch() can't read (e.g. a cross-origin redirect).
      return '''
(function(){
  function viaCanvas(){
    var im = new Image();
    im.onload = function(){
      try{
        var c = document.createElement('canvas');
        c.width = im.naturalWidth || 1; c.height = im.naturalHeight || 1;
        c.getContext('2d').drawImage(im, 0, 0);
        CFImg.postMessage(JSON.stringify({id:$id, ok:true, data:c.toDataURL('image/jpeg',0.92)}));
      }catch(e){ CFImg.postMessage(JSON.stringify({id:$id, ok:false, error:String(e)})); }
    };
    im.onerror = function(){ CFImg.postMessage(JSON.stringify({id:$id, ok:false, error:'load'})); };
    im.src = $u;
  }
  fetch($u, {credentials:'include'}).then(function(r){
    if(!r.ok) throw new Error('http '+r.status);
    return r.arrayBuffer();
  }).then(function(buf){
    var b = new Uint8Array(buf), s = '', CH = 0x8000;
    for (var i = 0; i < b.length; i += CH) {
      s += String.fromCharCode.apply(null, b.subarray(i, Math.min(i + CH, b.length)));
    }
    CFImg.postMessage(JSON.stringify({id:$id, ok:true, data:'base64,' + btoa(s)}));
  }).catch(function(){ viaCanvas(); });
})();
''';
    }
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
  im.src = $u;
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
          _lastNavReady = await _awaitContent(c, settle, readyJs);
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
  ///
  /// Returns whether the content is believed ready: with [readyJs], true
  /// only when the predicate actually fired (hitting the ceiling without it
  /// means the snapshot is likely content-less and shouldn't be cached);
  /// without one, always true — DOM stabilisation has no failure signal.
  Future<bool> _awaitContent(
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
          if (r.replaceAll('"', '').trim() == '1') return true;
        } else {
          final r = (await c
                  .runJavaScriptReturningResult(
                    "document.getElementsByTagName('*').length",
                  )
                  .timeout(const Duration(seconds: 5)))
              .toString();
          final n = int.tryParse(r.replaceAll('"', '').trim()) ?? -1;
          if (n >= 0 && n == lastCount) return true; // unchanged → settled
          lastCount = n;
        }
      } catch (_) {
        return readyJs == null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return readyJs == null;
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
    if (!mounted) return;
    final active = WebViewHttpClient.instance.activate.value;
    if (active && _controller == null) {
      setState(
        () => _controller = WebViewHttpClient.instance.buildController(),
      );
    } else if (!active && _controller != null) {
      // Idle teardown: dropping the WebViewWidget releases the platform view
      // (and its per-frame compositing cost); the next activation mounts a
      // fresh controller.
      setState(() => _controller = null);
    }
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
