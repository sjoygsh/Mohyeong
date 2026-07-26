import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/network/app_http_client.dart';
import '../../data/network/network_preferences.dart';
import '../../data/network/webview_cookie_sync.dart';

/// DEVELOPER-ONLY tool (not part of the shipping UI surface) for authoring
/// source extensions. Loads any URL in a WebView so the developer can click
/// through Cloudflare and let JS-rendered sites finish painting, harvests
/// the resulting cookies into the shared cookie jar (so an installed
/// extension's later HTTP requests are already cleared), then dumps the
/// fully-rendered DOM to `<appDocuments>/devdump.html` — pulled off-device
/// to read the real page structure and write the scraper's selectors.
class DevPageSourceScreen extends ConsumerStatefulWidget {
  const DevPageSourceScreen({super.key});

  @override
  ConsumerState<DevPageSourceScreen> createState() =>
      _DevPageSourceScreenState();
}

class _DevPageSourceScreenState extends ConsumerState<DevPageSourceScreen> {
  late final WebViewController _controller;
  final _urlField = TextEditingController();
  String _status = 'Enter a URL and tap Go.';

  /// Host of the page we asked for — pirate sites fire `intent://` / pop-up
  /// ad redirects that hijack the WebView, so we block any navigation to a
  /// different host (and non-http schemes) to keep the real page loaded.
  String? _baseHost;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Match the Dio UA so harvested cf_clearance validates for the
      // extension's later requests (see [defaultUserAgent]).
      ..setUserAgent(defaultUserAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme != 'http' && uri.scheme != 'https') {
            return NavigationDecision.prevent; // intent:, market:, etc.
          }
          final base = _baseHost;
          if (base != null && !_sameSite(uri.host, base)) {
            return NavigationDecision.prevent; // ad redirect to another host
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (url) {
          _urlField.text = url;
          _harvestCookies(url);
        },
      ));
  }

  /// True when [host] is the base host or a subdomain of its registrable
  /// part (so `www.` / CDN subdomains of the same site are allowed).
  bool _sameSite(String host, String base) {
    String reg(String h) {
      final p = h.split('.');
      return p.length <= 2 ? h : p.sublist(p.length - 2).join('.');
    }
    return reg(host) == reg(base);
  }

  Future<void> _go() async {
    final raw = _urlField.text.trim();
    if (raw.isEmpty) return;
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    _baseHost = Uri.parse(url).host;
    await _controller.loadRequest(Uri.parse(url));
    setState(() => _status = 'Loading $url …');
  }

  /// Reuses the Cloudflare-solver harvest so the shared Dio cookie jar gets
  /// cf_clearance for the host, making the installed extension work.
  Future<void> _harvestCookies(String url) async {
    // On Android the Dio client already shares the WebView's live cookie store
    // (see [WebViewCookieJar]), so nothing needs harvesting here. Only the
    // iOS/unsupported fallback copies the JS-visible cookies into the jar.
    if (await webViewHasClearance(url) != null) return; // native store in use
    try {
      final raw = await _controller
          .runJavaScriptReturningResult('document.cookie') as String;
      final cookieString = raw.replaceAll(RegExp(r'^"|"$'), '');
      if (cookieString.isEmpty) return;
      final cookies = <Cookie>[];
      for (final piece in cookieString.split(';')) {
        final t = piece.trim();
        final eq = t.indexOf('=');
        if (eq <= 0) continue;
        cookies.add(Cookie(t.substring(0, eq), t.substring(eq + 1)));
      }
      if (cookies.isEmpty) return;
      await ref
          .read(appHttpClientProvider)
          .cookies
          .saveFromResponse(Uri.parse(url), cookies);
    } catch (_) {
      // Best-effort; cookie sync isn't fatal to dumping the DOM.
    }
  }

  Future<void> _dump() async {
    try {
      final html = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      ) as String;
      // runJavaScriptReturningResult returns a JSON-encoded string on
      // Android — jsonDecode unwraps the quotes + \n/\"/\\ escapes back to
      // real HTML (HTML's own < > aren't JSON-escaped, so they pass through).
      var decoded = html;
      if (decoded.startsWith('"')) {
        try {
          decoded = jsonDecode(html) as String;
        } catch (_) {/* leave as-is */}
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/devdump.html');
      await file.writeAsString(decoded, flush: true);
      setState(() => _status = 'Dumped ${decoded.length} chars → ${file.path}');
    } catch (e) {
      setState(() => _status = 'Dump failed: $e');
    }
  }

  @override
  void dispose() {
    _urlField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Column(
        children: [
          const TideHeader(title: 'Dev: page source'),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlField,
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/manga/foo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _go(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _go, child: const Text('Go')),
                const SizedBox(width: 4),
                FilledButton.tonal(onPressed: _dump, child: const Text('Dump')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 4),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
