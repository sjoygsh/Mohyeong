import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/network/network_preferences.dart';
import '../../data/reader/reader_image_actions.dart';

/// Minimal in-app browser — the Flutter analog of Kotlin's `WebViewActivity`
/// / `WebViewScreenContent`. Used by the reader's "Open in WebView" overflow
/// action (and reusable anywhere a source page should open without leaving
/// the app). App bar shows [title] over the current page URL, with Kotlin's
/// overflow actions: Refresh / Open in browser / Share.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  late String _currentUrl = widget.url;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Parity with Kotlin WebViewScreenContent (userAgentString = default UA).
      ..setUserAgent(defaultUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _currentUrl = url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title ?? _currentUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.title != null)
              Text(
                _currentUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _controller.reload();
                case 'browser':
                  _openInBrowser();
                case 'share':
                  ReaderImageActions.shareText(_currentUrl);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              PopupMenuItem(value: 'browser', child: Text('Open in browser')),
              PopupMenuItem(value: 'share', child: Text('Share')),
            ],
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
