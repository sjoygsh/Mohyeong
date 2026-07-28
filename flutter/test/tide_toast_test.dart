import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/tide/tide.dart';

/// TideToast replaces ~50 Material SnackBars, so it inherits their contract:
/// it has to survive being captured before an await and fired after one, it
/// must not stack, and it has to take itself away again. The last one matters
/// most — a toast that leaks its OverlayEntry would sit on the screen forever.

Widget _host(void Function(TideToast toast) onTap) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: GestureDetector(
            // Captured on build, used on tap — the same shape as the real call
            // sites, which grab the handle before awaiting a repository.
            onTap: () => onTap(TideToast.of(context)),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(TideToast.clear);

  testWidgets('a toast appears, then takes itself away',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host((toast) => toast.show('Saved')));

    expect(find.text('Saved'), findsNothing);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);

    // Past the 3.2s dwell plus the entry animation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('a second toast replaces the first rather than stacking',
      (WidgetTester tester) async {
    late TideToast captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = TideToast.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    captured.show('First');
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    captured.show('Second');
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
  });

  testWidgets('a toast left on screen does not outlive the tree',
      (WidgetTester tester) async {
    // The regression this pins: the dwell used to be a bare Timer, which kept
    // running after the tree was gone — holding the overlay entry alive, and
    // failing EVERY unrelated widget test that happened to trigger a message
    // with "a Timer is still pending even after the widget tree was disposed".
    // This test deliberately ends while the toast is still up.
    await tester.pumpWidget(_host((toast) => toast.show('Still up')));
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Still up'), findsOneWidget);

    // Tear the tree down mid-dwell. If anything is still pending, the test
    // binding asserts during teardown and this fails.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an empty message shows nothing at all',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host((toast) => toast.show('')));
    await tester.tap(find.text('go'));
    await tester.pump();

    // Only the button; no pane of glass over an empty string.
    expect(find.byType(TideGlass), findsNothing);
  });

  testWidgets('an action is tappable and dismisses the toast',
      (WidgetTester tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _host((toast) => toast.show(
            'Copied',
            actionLabel: 'Undo',
            onAction: () => tapped++,
          )),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('UNDO'), findsOneWidget);

    // Let the rise finish so the target is where the hit test expects it.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('UNDO'));
    await tester.pump();

    expect(tapped, 1);
    expect(find.text('Copied'), findsNothing);
  });

  group('TideProgressBar', () {
    testWidgets('a determinate bar fills to its value',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: TideProgressBar(value: 0.25)),
          ),
        ),
      ));

      final fill = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fill.widthFactor, 0.25);
    });

    testWidgets('an out-of-range value is clamped rather than overflowing',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, child: TideProgressBar(value: 1.8)),
          ),
        ),
      ));

      final fill = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fill.widthFactor, 1.0);
      expect(tester.takeException(), isNull);
    });
  });
}
