import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/library/library_update_preference.dart';
import 'package:mohyeong/data/library/library_update_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// The device restrictions the background sweep runs under, against Kotlin
/// `LibraryUpdateJob.setupTask`'s constraint builder.
///
/// The one this port left out was `requiresBatteryNotLow`, which Kotlin sets
/// unconditionally — and which this app's own backup scheduler already sets,
/// naming it in its doc comment. A whole-library sweep is the last thing that
/// should run on a nearly-flat battery.
Future<Constraints> _constraints(List<String>? restrictions) async {
  SharedPreferences.setMockInitialValues({
    if (restrictions != null) 'library_update_restriction': restrictions,
  });
  return LibraryUpdateScheduler().buildConstraintsForTesting();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a flat battery holds the sweep off, whatever else is set', () async {
    for (final r in <List<String>?>[
      null,
      const <String>[],
      const [DeviceRestriction.onlyOnWifi],
      const [DeviceRestriction.charging],
    ]) {
      expect((await _constraints(r)).requiresBatteryNotLow, isTrue,
          reason: 'restrictions: $r');
    }
  });

  test('wifi-only and not-metered both ask for an unmetered network',
      () async {
    expect(
      (await _constraints(const [DeviceRestriction.onlyOnWifi])).networkType,
      NetworkType.unmetered,
    );
    expect(
      (await _constraints(const [DeviceRestriction.networkNotMetered]))
          .networkType,
      NetworkType.unmetered,
    );
  });

  test('with neither, any connection will do', () async {
    expect(
      (await _constraints(const <String>[])).networkType,
      NetworkType.connected,
    );
  });

  test('the default when nothing is stored is wifi-only, as in the fork',
      () async {
    expect((await _constraints(null)).networkType, NetworkType.unmetered);
  });

  test('charging is carried through', () async {
    expect(
      (await _constraints(const [DeviceRestriction.charging]))
          .requiresCharging,
      isTrue,
    );
    expect(
      (await _constraints(const <String>[])).requiresCharging,
      isFalse,
    );
  });
}
