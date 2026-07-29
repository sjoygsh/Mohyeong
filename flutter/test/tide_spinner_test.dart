import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/tide/tide.dart';

/// [TideSpinner] is now the app's only circular progress affordance — it
/// absorbed the last seven `CircularProgressIndicator`s, which needed two
/// things it did not have: a determinate mode (the chapter-row download ring)
/// and a colour override (the reader, whose page chrome sits on whichever
/// background the reader is set to and so cannot take the accent).
///
/// Both are states rather than pixels, and neither is provable by looking at
/// a screenshot of a spinning ring, so they are pinned here.

/// Whether anything is currently driving frames. A determinate ring has
/// nothing to animate and must not hold a ticker open — there is one of these
/// behind every downloading chapter in a list.
bool get _animating => WidgetsBinding.instance.hasScheduledFrame;

Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  testWidgets('an indeterminate ring travels; a determinate one holds still',
      (tester) async {
    await tester.pumpWidget(_host(const TideSpinner()));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_animating, isTrue,
        reason: 'work of unknown length has to read as motion');

    await tester.pumpWidget(_host(const TideSpinner(value: 0.4)));
    // Let the stopped controller's last frame drain.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_animating, isFalse,
        reason: 'a known fraction is not animation — do not hold a ticker '
            'open behind every download row');

    // ...and back, so a row that starts reporting progress and then stops
    // does not end up frozen.
    await tester.pumpWidget(_host(const TideSpinner()));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_animating, isTrue);

    // Leave nothing scheduled behind us.
    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('a determinate ring repaints when its fraction moves',
      (tester) async {
    await tester.pumpWidget(_host(const TideSpinner(value: 0.1)));
    final painter = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(TideSpinner),
        matching: find.byType(CustomPaint),
      ),
    );
    final first = painter.painter!;

    await tester.pumpWidget(_host(const TideSpinner(value: 0.9)));
    final next = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(TideSpinner),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    // Nothing else changes between these two frames, so a painter that
    // ignored `value` would silently render the ring stuck at 10%.
    expect(next.shouldRepaint(first), isTrue);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('the colour override reaches the paint', (tester) async {
    // The reader passes its own ink here: on the White background the accent
    // is wrong and the hard-coded `Colors.white` this replaced was invisible.
    await tester.pumpWidget(
      _host(const TideSpinner(value: 0.5, color: Colors.black)),
    );
    final black = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(TideSpinner),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    await tester.pumpWidget(_host(const TideSpinner(value: 0.5)));
    final accent = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(TideSpinner),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    expect(accent.shouldRepaint(black), isTrue,
        reason: 'the override has to survive as far as the painter');

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });
}
