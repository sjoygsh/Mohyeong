import 'package:flutter/material.dart';

import '../tide/tide.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Generic OAuth authorization-code flow screen.
///
/// Loads [authorizationUrl] in a webview and watches for navigations whose
/// URL starts with [redirectScheme]. When that match fires, parses the
/// `code` / `error` query parameter and pops the screen, returning either:
///   * a [String] containing the authorization code, or
///   * `null` if the user cancelled / the OAuth server returned an error.
///
/// The caller is then expected to exchange the code for an access token via
/// the tracker's token endpoint.
class OAuthWebViewScreen extends StatefulWidget {
  const OAuthWebViewScreen({
    super.key,
    required this.title,
    required this.authorizationUrl,
    required this.redirectScheme,
  });

  final String title;
  final String authorizationUrl;
  final String redirectScheme;

  @override
  State<OAuthWebViewScreen> createState() => _OAuthWebViewScreenState();
}

class _OAuthWebViewScreenState extends State<OAuthWebViewScreen> {
  late final WebViewController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _matchesRedirect(uri)) {
              _completeWith(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _matchesRedirect(Uri uri) {
    final raw = uri.toString();
    return raw.startsWith(widget.redirectScheme);
  }

  void _completeWith(Uri uri) {
    if (_completed) return;
    _completed = true;
    // OAuth servers either send `code` (success) or `error` (rejection).
    final code = uri.queryParameters['code'];
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TideHeader(
            title: widget.title,
            onBack: () {
              if (!_completed) {
                _completed = true;
                Navigator.of(context).pop(null);
              }
            },
          ),
          Expanded(child: WebViewWidget(controller: _controller),),
        ],
      ),
    );
  }
}
