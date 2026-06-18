import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/network/app_http_client.dart';
import '../../data/network/network_preferences.dart';
import '../../data/network/webview_cookie_sync.dart';

/// Opens [url] in a webview so the user can clear a Cloudflare interstitial.
/// On success (the `cf_clearance` cookie shows up in the webview's cookie
/// jar) the cookies are extracted and persisted into the shared cookie jar
/// used by every extension request. The user is then bounced back.
///
/// Both Cloudflare turnstile / "I'm Human" challenges and the JS-only
/// `__cf_chl_jschl_tk__` redirect flow are handled — once cf_clearance is
/// set, subsequent dio requests against the same host include it
/// automatically.
class CloudflareSolverScreen extends ConsumerStatefulWidget {
  const CloudflareSolverScreen({super.key, required this.url});

  final String url;

  @override
  ConsumerState<CloudflareSolverScreen> createState() =>
      _CloudflareSolverScreenState();
}

class _CloudflareSolverScreenState
    extends ConsumerState<CloudflareSolverScreen> {
  late final WebViewController _controller;
  Timer? _poll;
  bool _solved = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Must match the Dio UA so the cf_clearance we harvest validates for
      // subsequent extension requests (see [defaultUserAgent]).
      ..setUserAgent(defaultUserAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _maybeHarvestCookies(),
      ))
      ..loadRequest(Uri.parse(widget.url));
    // Poll in addition to onPageFinished: Cloudflare may set cf_clearance
    // mid-page without a navigation event.
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _maybeHarvestCookies(),
    );
  }

  /// True while the WebView is still showing a Cloudflare interstitial
  /// ("Just a moment…" / challenge / Turnstile). Harvesting during this state
  /// captures a *stale* cf_clearance (the previous, now-expired one that the
  /// browser still has on disk) and reports a false "solved", so we must wait
  /// for the real page before harvesting. Best-effort: any error → treat as
  /// not-a-challenge so we don't get stuck.
  Future<bool> _isChallengePage() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        "(function(){var t=(document.title||'').toLowerCase();"
        "var c=document.querySelector('#challenge-running,#cf-challenge-running,"
        "#challenge-form,.cf-turnstile,#turnstile-wrapper');"
        "return (t.indexOf('just a moment')>=0||t.indexOf('attention required')>=0"
        "||t.indexOf('verifying')>=0||c!=null)?'1':'0';})()",
      );
      return raw.toString().contains('1');
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeHarvestCookies() async {
    if (_solved) return;
    final http = ref.read(appHttpClientProvider);

    // Don't harvest while the challenge is still on screen — the cookie store
    // still holds the previous (expired) cf_clearance at that point.
    if (await _isChallengePage()) return;

    // Preferred path: read the native WebView cookie store, which includes
    // the HttpOnly cf_clearance cookie. `document.cookie` cannot see it, so
    // the old JS-only harvest never actually captured the clearance.
    final nativeCleared = await webViewHasClearance(widget.url);
    if (nativeCleared == true) {
      if (await syncWebViewCookies(http, widget.url)) {
        if (!mounted) return;
        setState(() => _solved = true);
        Navigator.of(context).pop(true);
        return;
      }
    }
    if (nativeCleared != null) return; // native channel handled it; not solved yet

    // Fallback (iOS / channel unavailable): JS harvest of visible cookies.
    final raw = await _controller
        .runJavaScriptReturningResult('document.cookie') as String;
    final cookieString = raw.replaceAll(RegExp(r'^"|"$'), '');
    if (!cookieString.contains('cf_clearance')) return;
    final uri = Uri.parse(widget.url);
    final cookies = _parseCookies(cookieString);
    await http.cookies.saveFromResponse(uri, cookies);
    if (!mounted) return;
    setState(() => _solved = true);
    Navigator.of(context).pop(true);
  }

  List<Cookie> _parseCookies(String header) {
    final result = <Cookie>[];
    for (final piece in header.split(';')) {
      final trimmed = piece.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq);
      final value = trimmed.substring(eq + 1);
      result.add(Cookie(name, value));
    }
    return result;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloudflare challenge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.all(8),
            child: Text(
              'Complete any challenge shown below. The page will close '
              'automatically once the Cloudflare cookie is set.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
