import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/library/library_update_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The v0.19 → v1.0 upgrade happens in place under the same applicationId, so
/// the Kotlin fork's preferences are still in the same store when the Flutter
/// app first runs. It writes the auto-update interval under
/// `pref_library_update_interval_key`; this app reads
/// `pref_library_update_interval_hours`. Same units, same numbers, different
/// name — so without a fallback the interval silently reverted to the Flutter
/// default, and someone who had set it to Off found their library updating
/// itself.
Future<LibraryUpdateInterval> _read(ProviderContainer c) async {
  // The notifier loads from disk asynchronously in build().
  c.read(libraryUpdatePreferenceProvider);
  await Future<void>.delayed(Duration.zero);
  return c.read(libraryUpdatePreferenceProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an upgraded install keeps the interval it had in the Kotlin app',
      () async {
    SharedPreferences.setMockInitialValues({
      'pref_library_update_interval_key': 48,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(await _read(c), LibraryUpdateInterval.every48h);
  });

  test('"Off" survives the upgrade — the case that mattered', () async {
    // 0 is the fork's default AND its "never update" choice. Falling back to
    // the Flutter default here is what started unrequested background work.
    SharedPreferences.setMockInitialValues({
      'pref_library_update_interval_key': 0,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(await _read(c), LibraryUpdateInterval.manual);
  });

  test('our own key wins when both are present', () async {
    SharedPreferences.setMockInitialValues({
      'pref_library_update_interval_hours': 168,
      'pref_library_update_interval_key': 12,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(await _read(c), LibraryUpdateInterval.weekly);
  });

  test('setting an interval drops the fork copy so they cannot disagree',
      () async {
    SharedPreferences.setMockInitialValues({
      'pref_library_update_interval_key': 12,
    });
    final store = await SharedPreferences.getInstance();
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c
        .read(libraryUpdatePreferenceProvider.notifier)
        .setInterval(LibraryUpdateInterval.weekly);

    expect(store.getInt('pref_library_update_interval_hours'), 168);
    expect(store.getInt('pref_library_update_interval_key'), isNull);
  });

  test('a fresh install reads nothing and keeps the fork\'s default: Off',
      () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    // `autoUpdateInterval` in `LibraryPreferences.kt` defaults to 0. This used
    // to default to `daily`, so a fresh install swept the whole library once a
    // day without ever being asked.
    expect(await _read(c), LibraryUpdateInterval.manual);
  });

  test('an unrecognised stored value does not start updating either', () async {
    SharedPreferences.setMockInitialValues({
      'pref_library_update_interval_hours': 6,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(await _read(c), LibraryUpdateInterval.manual);
  });
}
