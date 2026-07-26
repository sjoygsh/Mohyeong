import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mohyeong/data/base/base_preferences.dart';
import 'package:mohyeong/data/source/incognito_preferences.dart';
import 'package:mohyeong/presentation/more/more_screen.dart';
import 'package:mohyeong/presentation/tide/tide.dart';

/// More's two global modes are the only state on the hub, and Tide draws them
/// as rows that light up when they are on. That lighting is derived from the
/// preference, and a switch that moves without writing the preference would
/// look exactly the same — so the wiring is asserted, not the pixels.

Future<void> _pump(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the mode switches drive the real preferences',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    await _pump(tester);

    expect(container.read(downloadedOnlyProvider), isFalse);
    expect(container.read(incognitoModeProvider), isFalse);

    // Two modes, and nothing else on the screen carries a switch.
    expect(find.byType(TideSwitch), findsNWidgets(2));

    await tester.tap(find.byType(TideSwitch).first);
    await _pump(tester);
    expect(container.read(downloadedOnlyProvider), isTrue);
    expect(container.read(incognitoModeProvider), isFalse);

    // The row itself is the target too — tapping the label toggles the mode
    // rather than doing nothing, which is what a row with a switch on it
    // implies.
    await tester.tap(find.text('Incognito mode'));
    await _pump(tester);
    expect(container.read(incognitoModeProvider), isTrue);

    // And back off again, from the switch.
    await tester.tap(find.byType(TideSwitch).first);
    await _pump(tester);
    expect(container.read(downloadedOnlyProvider), isFalse);
  });

  testWidgets('the hub groups its destinations under named sections',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MoreScreen())),
    );
    await _pump(tester);

    expect(find.text('MODES'), findsOneWidget);
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);

    // Every destination the Kotlin hub offered is still here.
    for (final label in const [
      'Download queue',
      'Categories',
      'Statistics',
      'Data and storage',
      'Settings',
      'About',
      'Help',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
  });
}
