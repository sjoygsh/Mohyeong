import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';
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

  /// The cf_clearance value present when this screen opened (null after we
  /// clear it). We only accept a clearance whose value DIFFERS from this, so a
  /// stale cookie the WebView still has on disk isn't mistaken for a solve
  /// (mirrors Mihon's `nowCookie != preCookie`).
  String? _oldClearance;

  /// Give up auto-detecting after this long so the user isn't stuck on a
  /// challenge that needs no solve (already cleared) or won't auto-pass.
  static const _timeout = Duration(seconds: 30);

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
      ));
    // Clear any existing cf_clearance FIRST, then load — otherwise the WebView
    // reuses a clearance Chrome still accepts, Cloudflare never re-challenges,
    // and no fresh cookie is minted for the HTTP client (mirrors Mihon's
    // CloudflareInterceptor pre-solve removal). Capture the old value after the
    // clear so the post-solve value is guaranteed to differ.
    removeWebViewCookie(widget.url, 'cf_clearance').whenComplete(() async {
      _oldClearance = await webViewClearanceValue(widget.url);
      if (mounted) _controller.loadRequest(Uri.parse(widget.url));
    });
    // Poll in addition to onPageFinished: Cloudflare may set cf_clearance
    // mid-page without a navigation event.
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _maybeHarvestCookies(),
    );
    // Safety valve: stop waiting after [_timeout]. On Android the shared cookie
    // store means whatever clearance exists is already live for Dio, so we
    // dismiss as "done" and let the source retry; the user can re-open if it
    // still 403s (e.g. an interactive Turnstile they didn't complete in time).
    Timer(_timeout, () {
      if (!_solved && mounted) Navigator.of(context).pop(true);
    });
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

    // Don't act while the challenge is still on screen — the cookie store
    // still holds the previous (expired) cf_clearance at that point.
    if (await _isChallengePage()) return;

    // Android: Dio's cookie jar IS the WebView's live cookie store, so once a
    // FRESH cf_clearance (value differs from when we opened) appears there's
    // nothing to copy — just confirm and dismiss. Requiring a value change
    // avoids popping on the stale cookie the browser still had on disk.
    final value = await webViewClearanceValue(widget.url);
    if (value != null) {
      if (value == _oldClearance) return; // same stale clearance, keep waiting
      if (!mounted) return;
      setState(() => _solved = true);
      Navigator.of(context).pop(true);
      return;
    }
    // value == null here means either "no clearance yet" (Android, keep
    // waiting) or "native channel unavailable" (iOS) — fall through to the JS
    // harvest, which is a no-op on Android (document.cookie can't see it).
    final hasNative = await webViewHasClearance(widget.url);
    if (hasNative != null) return; // Android: channel works, just not solved yet

    // Fallback (iOS / channel unavailable): JS harvest of visible cookies
    // into the persistent jar. runJavaScriptReturningResult is platform-typed
    // (Object), so stringify rather than hard-cast.
    final raw = (await _controller
            .runJavaScriptReturningResult('document.cookie'))
        .toString();
    final cookieString = raw.replaceAll(RegExp(r'^"|"$'), '');
    if (!cookieString.contains('cf_clearance')) return;
    final uri = Uri.parse(widget.url);
    final cookies = _parseCookies(cookieString);
    await ref.read(appHttpClientProvider).cookies.saveFromResponse(uri, cookies);
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
      backgroundColor: TideColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TideHeader(
            title: 'Cloudflare challenge',
            actions: [
              TideIconButton(
                icon: Icons.refresh,
                onTap: () => _controller.reload(),
              ),
            ],
          ),
          Expanded(child: Column(
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
      ),),
        ],
      ),
    );
  }
}
