import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Singleton HTTP client + cookie jar shared by every extension runtime,
/// the download manager, and any other host-side fetcher.
///
/// Cookies are persisted to disk so Cloudflare `cf_clearance` cookies (solved
/// once via the webview) survive across app launches and apply to every
/// subsequent extension request automatically.
class AppHttpClient {
  AppHttpClient._(this.dio, this.cookies);

  final Dio dio;
  final PersistCookieJar cookies;

  static AppHttpClient? _instance;

  static Future<AppHttpClient> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final cookieDir = p.join(support.path, 'cookies');
    final jar = PersistCookieJar(
      storage: FileStorage(cookieDir),
      ignoreExpires: false,
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
    final dio = Dio()..interceptors.add(CookieManager(jar));
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
