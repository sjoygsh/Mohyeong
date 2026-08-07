import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/source/browse_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference keys are an on-disk contract shared with the Kotlin app: the
/// v0.19 → v1.0 upgrade happens in place under the same applicationId, and
/// backups replay entries by key.
///
/// "Hide entries already in library" was stored under
/// `pref_hide_in_library_items` — which is the fork's STRING RESOURCE id for
/// the switch's label, not its storage key (`browse_hide_in_library_items`).
/// The two sit next to each other in `SettingsBrowseScreen`, and reading the
/// wrong one meant an upgrade silently dropped the choice.
Future<bool> _read(ProviderContainer c) async {
  c.read(hideInLibraryItemsProvider);
  await Future<void>.delayed(Duration.zero);
  return c.read(hideInLibraryItemsProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the value written by the Kotlin app is honoured', () async {
    SharedPreferences.setMockInitialValues({
      'browse_hide_in_library_items': true,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await _read(c), isTrue);
  });

  test('a value stored under the old wrong key is not lost', () async {
    SharedPreferences.setMockInitialValues({
      'pref_hide_in_library_items': true,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await _read(c), isTrue);
  });

  test('the real key wins when both are present', () async {
    SharedPreferences.setMockInitialValues({
      'browse_hide_in_library_items': false,
      'pref_hide_in_library_items': true,
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await _read(c), isFalse);
  });

  test('writing moves the value onto the real key and drops the old one',
      () async {
    SharedPreferences.setMockInitialValues({
      'pref_hide_in_library_items': true,
    });
    final store = await SharedPreferences.getInstance();
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(hideInLibraryItemsProvider.notifier).set(true);

    expect(store.getBool('browse_hide_in_library_items'), isTrue);
    expect(store.getBool('pref_hide_in_library_items'), isNull);
  });

  test('a fresh install keeps the default', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await _read(c), isFalse);
  });
}
