import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/services.dart';

/// Bridge to the native Android WebView [CookieManager] plus a [CookieJar]
/// that is backed by it.
///
/// The whole point: on Android the WebView and the app's HTTP (Dio) client
/// must share ONE live cookie store. Cloudflare rotates companion cookies
/// (`__cf_bm`) and refreshes `cf_clearance`; a one-time snapshot copied into a
/// separate jar goes stale and the next request 403s. Mihon avoids this by
/// making OkHttp's `CookieJar` read straight from `CookieManager` on every
/// request (see Kotlin `AndroidCookieJar`). [WebViewCookieJar] does the same
/// for Dio: every `loadForRequest` reads the *current* cookies the WebView
/// holds, so a freshly-solved challenge authenticates the very next request.
///
/// `CookieManager` also exposes HttpOnly cookies (which `cf_clearance` is) —
/// something `document.cookie` cannot — so no JS harvest is needed on Android.
///
/// The native `app.mohyeong/webview_cookies` channel is registered only on the
/// UI [FlutterEngine]. In the WorkManager background isolate the channel isn't
/// there, so every native call throws [MissingPluginException]; the jar
/// transparently falls back to the persistent [CookieJar] (which is mirrored on
/// every foreground save) so background library updates still send cookies.
const _channel = MethodChannel('app.mohyeong/webview_cookies');

/// Raw `k=v; k=v` cookie string the WebView holds for [url] (HttpOnly
/// included), or null when the native channel is unavailable (e.g. iOS, or the
/// headless background isolate).
Future<String?> nativeCookieString(String url) async {
  try {
    return await _channel.invokeMethod<String>('getCookie', {'url': url});
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<void> _nativeSetCookie(String url, String value) async {
  try {
    await _channel.invokeMethod<void>('setCookie', {'url': url, 'value': value});
  } on PlatformException {
    // ignore
  } on MissingPluginException {
    // ignore
  }
}

Future<void> _nativeFlush() async {
  try {
    await _channel.invokeMethod<void>('flush');
  } on PlatformException {
    // ignore
  } on MissingPluginException {
    // ignore
  }
}

Future<void> _nativeClearAll() async {
  try {
    await _channel.invokeMethod<void>('clearAll');
  } on PlatformException {
    // ignore
  } on MissingPluginException {
    // ignore
  }
}

/// Multi-label public suffixes where the registrable domain is the last THREE
/// labels (e.g. `site.co.uk`). Not the full Public Suffix List, but covers the
/// ccTLDs manga sites actually use; anything else uses the last two labels.
const _multiPartSuffixes = {
  'co.uk', 'org.uk', 'me.uk', 'com.au', 'net.au', 'co.jp', 'com.br', 'co.kr',
  'com.cn', 'co.in', 'com.mx', 'com.tr', 'co.za', 'com.tw', 'co.id', 'com.hk',
  'com.sg', 'co.th', 'com.ua', 'com.ph', 'com.vn',
};

/// The registrable ("apex") domain of [host] — e.g. `www.a.example.com` →
/// `example.com`, `a.site.co.uk` → `site.co.uk`. Used both to clear
/// Cloudflare's apex `cf_clearance` cookie and to decide same-site navigation.
String registrableDomain(String host) {
  final p = host.split('.');
  if (p.length <= 2) return host;
  final lastTwo = p.sublist(p.length - 2).join('.');
  if (p.length >= 3 && _multiPartSuffixes.contains(lastTwo)) {
    return p.sublist(p.length - 3).join('.');
  }
  return lastTwo;
}

/// Expire [name] for [url] in the shared store. Clearing `cf_clearance` before
/// (re)solving forces Cloudflare to mint a fresh challenge instead of the
/// WebView silently reusing a clearance that has gone stale for the HTTP
/// client (mirrors Mihon's `CloudflareInterceptor` pre-solve cookie removal).
Future<void> removeWebViewCookie(String url, String name) async {
  // Cloudflare sets cf_clearance on the registrable (apex) domain, so pass it
  // explicitly — clearing only the host cookie leaves the apex one in place.
  String? apex;
  final host = Uri.tryParse(url)?.host;
  if (host != null && host.isNotEmpty) apex = registrableDomain(host);
  try {
    await _channel.invokeMethod<void>('removeCookie', {
      'url': url,
      'name': name,
      'domain': ?apex,
    });
  } on PlatformException {
    // ignore
  } on MissingPluginException {
    // ignore
  }
}

/// Whether the WebView's native cookie store for [url] contains a Cloudflare
/// clearance cookie — i.e. the challenge has been solved. Returns null when
/// the native channel is unavailable so callers can fall back to a JS check.
Future<bool?> webViewHasClearance(String url) async {
  final raw = await nativeCookieString(url);
  if (raw == null) return null;
  return raw.contains('cf_clearance');
}

/// The current `cf_clearance` value the WebView holds for [url], or null if
/// none / the native channel is unavailable. The solver compares this before
/// and after solving so it only accepts a *freshly minted* clearance (mirrors
/// Mihon's `nowCookie != preCookie` check) rather than reusing a stale one.
Future<String?> webViewClearanceValue(String url) async {
  final raw = await nativeCookieString(url);
  if (raw == null) return null;
  for (final piece in raw.split(';')) {
    final t = piece.trim();
    if (t.startsWith('cf_clearance=')) return t.substring('cf_clearance='.length);
  }
  return null;
}

List<Cookie> _parsePairs(String header) {
  final result = <Cookie>[];
  for (final piece in header.split(';')) {
    final t = piece.trim();
    if (t.isEmpty) continue;
    final eq = t.indexOf('=');
    if (eq <= 0) continue;
    try {
      result.add(Cookie(t.substring(0, eq), t.substring(eq + 1)));
    } catch (_) {
      // Skip malformed pairs.
    }
  }
  return result;
}

String _serialize(Cookie c) {
  final sb = StringBuffer('${c.name}=${c.value}');
  if (c.domain != null) sb.write('; Domain=${c.domain}');
  sb.write('; Path=${c.path ?? '/'}');
  if (c.expires != null) {
    sb.write('; Expires=${HttpDate.format(c.expires!)}');
  }
  if (c.secure) sb.write('; Secure');
  if (c.httpOnly) sb.write('; HttpOnly');
  return sb.toString();
}

/// [CookieJar] that shares the native Android WebView cookie store on Android,
/// merging it over a persistent [CookieJar] that is also kept as a mirror.
///
/// * Foreground (channel available): native is authoritative/live (so a solved
///   `cf_clearance` applies immediately); the persistent jar mirrors every Dio
///   save so the background isolate can still read those cookies.
/// * Background isolate / iOS / desktop (channel unavailable): native calls
///   throw and are caught, so the jar falls back to the persistent mirror.
class WebViewCookieJar implements CookieJar {
  WebViewCookieJar(this._fallback);

  final CookieJar _fallback;

  bool get _useNative => Platform.isAndroid;

  @override
  bool get ignoreExpires => false;

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    if (!_useNative) return _fallback.loadForRequest(uri);
    // Hot path: the native store is the live superset in the foreground (every
    // Dio save mirrors into it, and the WebView writes cf_clearance there), so
    // when it has cookies we return them without also touching the persistent
    // mirror. Only fall back when native is unavailable (headless background
    // isolate) or genuinely empty.
    final raw = await nativeCookieString(uri.toString());
    if (raw != null && raw.isNotEmpty) return _parsePairs(raw);
    return _fallback.loadForRequest(uri);
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    if (cookies.isEmpty) return;
    // Always mirror into the persistent jar (primary off-Android; background
    // readability on Android).
    await _fallback.saveFromResponse(uri, cookies);
    if (!_useNative) return;
    final url = uri.toString();
    for (final c in cookies) {
      await _nativeSetCookie(url, _serialize(c));
    }
    await _nativeFlush();
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    await _fallback.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    await _fallback.deleteAll();
    if (_useNative) await _nativeClearAll();
  }
}
