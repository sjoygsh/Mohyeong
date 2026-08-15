import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/presentation/tide/tide_wordmark.dart';

/// Counts how many times its State was created, so a remount is visible.
class _Probe extends StatefulWidget {
  const _Probe();

  static int inits = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) => const Text('app body');
}

void main() {
  // ONE test: the gate plays once per process via a private static, so a
  // second test in this file would silently get the pass-through path and
  // prove nothing.
  testWidgets('the wordmark hands over without remounting the app beneath it',
      (tester) async {
    _Probe.inits = 0;
    await tester.pumpWidget(
      const MaterialApp(
        home: TideSplashGate(child: _Probe()),
      ),
    );

    // The child is alive underneath from the very first frame — the veil hides
    // it, it does not replace it. That is what lets the app finish booting
    // while the veil is still up.
    expect(_Probe.inits, 1);
    expect(find.byType(TideWordmark), findsOneWidget);
    expect(find.text('app body'), findsOneWidget);

    // Comfortably past fade-in + hold + fade-out (~0.9s). Explicit pumps, never
    // pumpAndSettle: the aurora behind the wordmark is a continuous animation
    // by design, so the frame queue never drains and pumpAndSettle would
    // simply time out.
    for (var i = 0; i < 55; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Veil gone, app still there…
    expect(find.byType(TideWordmark), findsNothing);
    expect(find.text('app body'), findsOneWidget);
    // …and crucially built exactly once. Handing back `widget.child` bare
    // instead of leaving it in slot 0 of the same Stack moves it in the
    // element tree and remounts the whole app a second into every cold start,
    // dropping HomeScreen's tab pre-warm and any other screen state with it.
    expect(_Probe.inits, 1);
  });
}
