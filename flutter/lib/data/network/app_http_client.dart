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
