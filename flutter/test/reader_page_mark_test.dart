import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/reader/page_mark.dart';

/// A continuous-reader page reserves its REAL extent as soon as its aspect is
/// known — two to four screens for a long strip — and read-ahead learns that
/// aspect before the page's bitmap arrives. So the box is routinely correct
/// and empty, and whatever it shows while it waits has to be visible from
/// anywhere inside it. Centring one spinner in a page-tall box puts it a
/// screen or two below the viewport: what the reader sees is a band of empty
/// background, every few pages, wherever the one-at-a-time download queue has
/// not caught up.
///
/// Two properties carry the fix, and both are properties of the LAYOUT:
///
///   1. Wherever you are parked inside the reservation, a mark is in sight.
///   2. The reservation is still exactly the height it was asked for — the
///      strip's offset↔index maths (progress, resume) is built on it.
void main() {
  const viewport = Size(400, 800);

  /// The marked page inside a scrollable [viewport]-sized window, as the
  /// strip lays it out: a box of exactly [total] pixels.
  Widget page({
    required double total,
    ScrollController? controller,
    Widget? leading,
  }) {
    return MediaQuery(
      data: const MediaQueryData(size: viewport),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          controller: controller,
          child: markedDownPage(
            total: total,
            viewport: viewport.height,
            leading: leading,
            mark: const Text('loading'),
          ),
        ),
      ),
    );
  }

  testWidgets('a mark is in sight from anywhere in a page-tall reservation',
      (tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Three and a half screens — an ordinary long-strip page.
    const total = 2800.0;
    final controller = ScrollController();
    await tester.pumpWidget(page(total: total, controller: controller));

    for (var offset = 0.0; offset <= total - viewport.height; offset += 100) {
      controller.jumpTo(offset);
      await tester.pump();
      final onScreen = tester
          .widgetList<Text>(find.text('loading'))
          .where((_) => true)
          .length;
      expect(onScreen, greaterThan(0),
          reason: 'no mark rendered at offset $offset');
      // Rendered is not enough — it has to be inside the window.
      final visible = find.text('loading').evaluate().where((element) {
        final box = element.renderObject! as RenderBox;
        final top = box.localToGlobal(Offset.zero).dy;
        return top >= 0 && top <= viewport.height;
      });
      expect(visible, isNotEmpty,
          reason: 'every mark was off-screen at offset $offset');
    }
  });

  testWidgets('the reservation keeps exactly the height it was asked for',
      (tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final total in <double>[120, 800, 2800, 40000]) {
      await tester.pumpWidget(page(total: total));
      final column = tester.renderObject<RenderBox>(find.byType(Column));
      expect(column.size.height, total,
          reason: 'reservation of $total px did not hold its extent');
    }
  });

  testWidgets('a wild extent estimate cannot spawn an unbounded column',
      (tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(page(total: 400000));
    expect(find.text('loading').evaluate().length,
        lessThanOrEqualTo(maxPageMarks));
  });

  testWidgets('the leading cell holds the page itself, one viewport tall',
      (tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      page(total: 2800, leading: const Placeholder()),
    );
    final leading = tester.renderObject<RenderBox>(find.byType(Placeholder));
    expect(leading.size.height, viewport.height);
    expect(leading.localToGlobal(Offset.zero).dy, 0);
  });

  testWidgets('a one-viewport box (the pager) gets a single centred mark',
      (tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: viewport),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: PageMark(mark: Text('loading')),
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);
    final mark = tester.renderObject<RenderBox>(find.text('loading'));
    final centre = mark.localToGlobal(Offset.zero).dy + mark.size.height / 2;
    expect(centre, closeTo(viewport.height / 2, 1));
  });
}
