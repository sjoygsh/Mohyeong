import 'dart:io';

import 'package:flutter/services.dart';

import 'app_http_client.dart';

/// Bridge to the native Android WebView [CookieManager]. Unlike a WebView's
/// `document.cookie` (which a JS harvest can read), the native cookie store
/// also holds **HttpOnly** cookies — and Cloudflare's `cf_clearance` is
/// HttpOnly. Harvesting via `document.cookie` therefore silently dropped the
/// one cookie that matters, so a "solved" challenge never authenticated the
/// shared Dio client. This channel reads the real cookie string instead.
const _channel = MethodChannel('app.mohyeong/webview_cookies');

/// Returns the full `k=v; k=v` cookie string the WebView holds for [url],
/// including HttpOnly cookies, or null when unavailable (e.g. on iOS, where
/// the channel isn't implemented — callers should fall back to a JS harvest).
Future<String?> _nativeCookieString(String url) async {
  try {
    return await _channel.invokeMethod<String>('getCookie', {'url': url});
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

List<Cookie> _parse(String header) {
  final result = <Cookie>[];
  for (final piece in header.split(';')) {
    final t = piece.trim();
    if (t.isEmpty) continue;
    final eq = t.indexOf('=');
    if (eq <= 0) continue;
    try {
      result.add(Cookie(t.substring(0, eq), t.substring(eq + 1)));
    } catch (_) {
      // Skip malformed cookie pairs.
    }
  }
  return result;
}

/// Harvests every cookie the WebView holds for [url] (HttpOnly included) into
/// the shared Dio cookie jar so the extension's subsequent HTTP requests are
/// authenticated. Returns true when at least one cookie was persisted.
Future<bool> syncWebViewCookies(AppHttpClient http, String url) async {
  final raw = await _nativeCookieString(url);
  if (raw == null || raw.isEmpty) return false;
  final cookies = _parse(raw);
  if (cookies.isEmpty) return false;
  await http.cookies.saveFromResponse(Uri.parse(url), cookies);
  return true;
}

/// Whether the WebView's native cookie store for [url] contains a Cloudflare
/// clearance cookie — i.e. the challenge has been solved. Returns null when
/// the native channel is unavailable so callers can fall back to a JS check.
Future<bool?> webViewHasClearance(String url) async {
  final raw = await _nativeCookieString(url);
  if (raw == null) return null;
  return raw.contains('cf_clearance');
}
