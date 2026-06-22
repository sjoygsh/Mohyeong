import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'network_preferences.dart';
import 'webview_cookie_sync.dart';

/// Singleton HTTP client + cookie jar shared by every extension runtime,
/// the download manager, and any other host-side fetcher.
///
/// On Android the jar is backed by the WebView's native `CookieManager`
/// ([WebViewCookieJar]) so Dio and the Cloudflare-solver WebView share ONE
/// live cookie store — a freshly-solved `cf_clearance` (and the rotating
/// `__cf_bm`) apply to the very next request without going stale. A
/// [PersistCookieJar] backs the non-Android fallback and survives restarts.
class AppHttpClient {
  AppHttpClient._(this.dio, this.cookies);

  final Dio dio;
  final CookieJar cookies;

  static AppHttpClient? _instance;

  static Future<AppHttpClient> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final cookieDir = p.join(support.path, 'cookies');
    final jar = WebViewCookieJar(
      PersistCookieJar(
        storage: FileStorage(cookieDir),
        ignoreExpires: false,
      ),
    );
    // TODO(doh): the `doh_provider` pref (network_preferences.dart) is stored
    // but not yet applied. To honour it, swap the plain `Dio()` for
    // `Dio()..httpClientAdapter = IOHttpClientAdapter(createHttpClient: ...)`
    // here (the single shared Dio, so this one site covers the whole app).
    // The factory resolves the host via a DoH JSON GET (provider URL +
    // bootstrap IP table ported from Mihon's DohProviders.kt), dials the
    // resolved IP, then `SecureSocket.secure(socket, host: originalHost)` so
    // SNI + cert validation still key off the real hostname. Deferred until
    // after real-server parity (TLS edge cases + IPv6/proxy/TTL caching).
    // Timeouts mirror Mihon's OkHttp (30s connect/read, 2 min call) so a
    // stalled connection — e.g. a Cloudflare-challenged endpoint that holds the
    // socket — fails fast and lets the WebView fallback kick in, instead of
    // hanging the extension's request (Dio has NO timeout by default).
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ))..interceptors.add(CookieManager(jar));
    // Mirrors Kotlin's UserAgentInterceptor: stamp the default browser UA on
    // every request that doesn't already carry one. Required for Cloudflare —
    // `cf_clearance` is minted against this exact UA in the solver WebView, so
    // Dio must replay the same string or the cookie is rejected. Also stops
    // sites that block Dio's default `Dio/x` agent outright.
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final existing = options.headers['User-Agent'] ??
              options.headers['user-agent'];
          if (existing == null || (existing is String && existing.isEmpty)) {
            options.headers['User-Agent'] = defaultUserAgent;
          }
          handler.next(options);
        },
      ),
    );
    final c = AppHttpClient._(dio, jar);
    _instance = c;
    return c;
  }
}

/// Riverpod handle for the shared client. Overridden in `main()` after the
/// async init completes.
final appHttpClientProvider = Provider<AppHttpClient>((ref) {
  throw UnimplementedError(
    'AppHttpClient must be overridden in main() once instance() resolves.',
  );
});
