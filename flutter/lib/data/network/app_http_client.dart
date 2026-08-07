import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call_timeout_adapter.dart';
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

  static Future<AppHttpClient>? _instance;

  /// Memoises the in-flight future, not the finished client: two concurrent
  /// first callers must not each build a Dio + PersistCookieJar over the same
  /// on-disk cookie directory (the await below is a real suspension point).
  ///
  /// A FAILED build is dropped rather than memoised. [_create] awaits
  /// `getApplicationSupportDirectory()` and `SharedPreferences.getInstance()`,
  /// both of which can fail transiently — most plausibly in the WorkManager
  /// background isolate, which builds its own client and whose plugin
  /// registrations come up independently of the UI engine's. Caching the
  /// rejected future would mean that isolate never makes another HTTP request
  /// for the rest of its life: no library sweep, no download, no extension
  /// fetch, with nothing to do but wait for the process to die.
  /// [ExtensionRepository] already applies this rule to its per-source
  /// in-flight map; this one site was missed.
  static Future<AppHttpClient> instance() =>
      _instance ??= _create().onError((Object error, StackTrace stack) {
        _instance = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<AppHttpClient> _create() async {
    final support = await getApplicationSupportDirectory();
    final cookieDir = p.join(support.path, 'cookies');
    final jar = WebViewCookieJar(
      PersistCookieJar(
        storage: FileStorage(cookieDir),
        ignoreExpires: false,
      ),
    );
    // TODO(doh): no DoH resolver yet. The ids + label table survive in
    // network_preferences.dart for this work, but there is deliberately no
    // settings picker writing `doh_provider` until the resolver exists — a
    // picker that stores a provider nobody dials tells the user their DNS is
    // private when it is not. To honour it, swap the plain `Dio()` for
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
    // The 2-minute call ceiling the comment above promised. Dio has no
    // `callTimeout`, and its `receiveTimeout` measures the gap between chunks
    // of a streamed response, so a server dribbling a few bytes a minute
    // satisfies every timeout Dio owns, forever. See [CallTimeoutAdapter].
    dio.httpClientAdapter = CallTimeoutAdapter(dio.httpClientAdapter);
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
    // Mirrors NetworkHelper: verbose logging attaches OkHttp's
    // HttpLoggingInterceptor at Level.HEADERS, so headers are logged but
    // bodies are not — page blobs would drown logcat. Read straight from
    // SharedPreferences because this runs in `main()` before the Riverpod
    // container exists, and because the download manager touches the same
    // client from the background isolate. Like Kotlin's, the level is fixed
    // for the life of the client: the toggle needs a restart, which its
    // subtitle in Advanced settings says.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(verboseLoggingKey) ?? false) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: true,
          responseHeader: true,
          requestBody: false,
          responseBody: false,
        ),
      );
    }
    return AppHttpClient._(dio, jar);
  }
}

/// Riverpod handle for the shared client. Overridden in `main()` after the
/// async init completes.
final appHttpClientProvider = Provider<AppHttpClient>((ref) {
  throw UnimplementedError(
    'AppHttpClient must be overridden in main() once instance() resolves.',
  );
});
