import 'package:flutter/material.dart';

import '../tide/tide.dart';
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

  Future<void> _openActions() async {
    final picked = await showTideSheet<String>(
      context,
      (_) => const TideOptionSheet(
        title: 'Page',
        options: [
          ('refresh', 'Refresh'),
          ('browser', 'Open in browser'),
          ('share', 'Share link'),
        ],
        selected: '',
      ),
    );
    switch (picked) {
      case 'refresh':
        await _controller.reload();
      case 'browser':
        await _openInBrowser();
      case 'share':
        await ReaderImageActions.shareText(_currentUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TideHeader(
            title: widget.title ?? _currentUrl,
            subtitle: widget.title == null ? null : _currentUrl,
            actions: [
              TideIconButton(
                icon: Icons.more_horiz,
                onTap: _openActions,
              ),
            ],
          ),
          // The app bar carried a LinearProgressIndicator; a lit hairline
          // under the header says the same thing without a slab.
          SizedBox(
            height: 2,
            child: _progress >= 100
                ? null
                : Row(
                    children: [
                      Expanded(
                        flex: _progress.clamp(0, 100),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: TideColors.accent,
                            boxShadow: [
                              BoxShadow(
                                color: TideColors.accent
                                    .withValues(alpha: 0.7),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: (100 - _progress).clamp(0, 100),
                        child: const SizedBox.shrink(),
                      ),
                    ],
                  ),
          ),
          Expanded(child: WebViewWidget(controller: _controller),),
        ],
      ),
    );
  }
}
