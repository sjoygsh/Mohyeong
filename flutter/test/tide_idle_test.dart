import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/tide/tide.dart';

/// Tide's decoration animates forever. Measured on device, an untouched screen
/// cost half a core and 160MB of graphics memory continuously, and the same app
/// backgrounded cost 0.0% — the whole bill was drawing a picture nobody was
/// watching. [TideIdle] is what lets it sleep.
///
/// The failure this pins is silent: if the aurora stops waking up, nothing
/// throws and no screen looks wrong at a glance. It just quietly freezes the
/// ground the first time you put the phone down, forever.

void main() {
  setUp(TideIdle.resetForTest);
  tearDown(TideIdle.resetForTest);

  testWidgets('the aurora animates, sleeps when untouched, and wakes on a tap',
      (WidgetTester tester) async {
    TideIdle.install();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [Positioned.fill(child: TideAurora())])),
      ),
    );

    // Awake: the blob tickers keep asking for frames.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'the aurora should be drifting while the app is awake');

    // Sleep. Past the idle threshold with no pointer event, the drift stops
    // and nothing asks for another frame — which is the entire point.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(milliseconds: 16));
    expect(TideIdle.awake.value, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'an untouched screen must stop producing frames');

    // Any touch brings it back.
    await tester.tap(find.byType(TideAurora), warnIfMissed: false);
    await tester.pump();
    expect(TideIdle.awake.value, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'a tap must wake the drift back up');

    // Let it settle so the test does not leave a live ticker behind.
    TideIdle.resetForTest();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('waking resumes the drift rather than snapping it back to zero',
      (WidgetTester tester) async {
    // The reason the pause is hand-driven instead of `repeat()`: repeat always
    // restarts at its lower bound, which would visibly jerk the whole ground
    // back to the start of its cycle every time you picked the phone up.
    TideIdle.install();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [Positioned.fill(child: TideAurora())])),
      ),
    );

    final atStart = _driftFingerprint(tester);

    // Let the blobs drift well away from their start, then sleep.
    await tester.pump(const Duration(seconds: 5));
    final drifted = _driftFingerprint(tester);
    expect((drifted - atStart).abs(), greaterThan(1.0),
        reason: 'the blobs should have moved off their start by now');

    await tester.pump(const Duration(seconds: 11));
    expect(TideIdle.awake.value, isFalse);
    final frozen = _driftFingerprint(tester);

    TideIdle.poke();
    await tester.pump();
    expect(_driftFingerprint(tester), closeTo(frozen, 0.01),
        reason: 'resume must continue from where it froze, not restart');

    TideIdle.resetForTest();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// A single number standing for where all three blobs currently sit.
///
/// The blob widget and its controller are private, so the animation is read
/// back through the transforms it drives. Summing all three (rather than
/// sampling one) avoids the trap that a single blob's drift crosses zero
/// mid-cycle and would read as "not moving".
double _driftFingerprint(WidgetTester tester) {
  var sum = 0.0;
  for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
    final v = t.transform.getTranslation();
    sum += v.x.abs() + v.y.abs();
  }
  return sum;
}
