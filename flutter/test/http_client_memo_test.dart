import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/network/app_http_client.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `AppHttpClient.instance()` memoises the in-flight future so concurrent first
/// callers share one Dio + cookie jar. The hazard is what it memoises on
/// FAILURE: `_create` awaits path_provider and SharedPreferences, and a
/// rejected future left in the static would be handed to every later caller
/// forever — in the WorkManager isolate that means no sweep, no download and
/// no extension fetch for the life of the process.
class _FailFirstPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FailFirstPathProvider(this.dir);

  final String dir;
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    if (calls == 1) {
      throw Exception('application support directory unavailable');
    }
    return dir;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a build that fails once does not poison every later request', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = _FailFirstPathProvider(
      Directory.systemTemp.createTempSync('mohyeong_http').path,
    );
    PathProviderPlatform.instance = provider;

    await expectLater(AppHttpClient.instance(), throwsA(isA<Exception>()));

    // Without the drop-on-failure this returns the SAME rejected future and
    // path_provider is never asked a second time.
    final client = await AppHttpClient.instance();
    expect(provider.calls, 2);
    expect(client.dio.options.connectTimeout, const Duration(seconds: 30));

    // And the successful one IS memoised — identical instance, no third call.
    expect(await AppHttpClient.instance(), same(client));
    expect(provider.calls, 2);
  });
}
