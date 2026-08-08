import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reader's continuous strip resumes by pinning the resumed page to
/// scroll offset 0 with a `center` sliver, rather than by jumping to a pixel
/// offset guessed from undecoded page heights. Two properties carry that fix,
/// and both are properties of the LAYOUT, not of anything the reader can
/// assert about itself — so they are pinned here, on the same sliver
/// arrangement `_PagesView` builds.
///
///   1. The anchored item is the one on screen at rest.
///   2. A page ABOVE the anchor growing (its bitmap arrives, and it goes from
///      the 400px placeholder to its real height) does not move the anchor.
///
/// (2) is the whole bug: the old pixel jump landed near the right page and
/// then watched it slide away as the pages above it decoded and pushed the
/// content down, which is why leaving a chapter on page 5 reopened it on
/// page 1.
void main() {
  /// Mirror of the strip: a reversed leading sliver for everything above
  /// [anchor], the centre sliver for the anchor and everything after.
  Widget strip({
    required int anchor,
    required int count,
    required double Function(int index) heightOf,
    required GlobalKey centerKey,
    ScrollController? controller,
    Set<int>? built,
  }) {
    Widget item(int i) {
      built?.add(i);
      return SizedBox(
        height: heightOf(i),
        child: Text('page $i', textDirection: TextDirection.ltr),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: CustomScrollView(
        controller: controller,
        center: centerKey,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => item(anchor - 1 - i),
              childCount: anchor,
            ),
          ),
          SliverList(
            key: centerKey,
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => item(anchor + i),
              childCount: count - anchor,
            ),
          ),
        ],
      ),
    );
  }

  testWidgets('the strip opens on the anchored page, not the first one',
      (tester) async {
    final centerKey = GlobalKey();
    await tester.pumpWidget(strip(
      anchor: 5,
      count: 40,
      heightOf: (_) => 400,
      centerKey: centerKey,
    ));

    final top = tester.getTopLeft(find.text('page 5')).dy;
    expect(top, 0, reason: 'the resumed page sits at the top of the viewport');
    expect(find.text('page 0'), findsNothing);
  });

  testWidgets('pages above the anchor are not built until scrolled into',
      (tester) async {
    final centerKey = GlobalKey();
    final built = <int>{};
    await tester.pumpWidget(strip(
      anchor: 20,
      count: 40,
      heightOf: (_) => 400,
      centerKey: centerKey,
      built: built,
    ));

    // Resuming deep into a chapter must not drag every page above the resume
    // point into existence — each one built is a fetch and a full-size decode.
    expect(built.where((i) => i < 19), isEmpty);
  });

  testWidgets('a page above the anchor growing does not move the anchor',
      (tester) async {
    final centerKey = GlobalKey();
    final controller = ScrollController();
    // Every page above the anchor is still on its placeholder height.
    var decoded = false;
    double heightOf(int i) => (!decoded && i < 5) ? 400 : 1600;

    await tester.pumpWidget(StatefulBuilder(
      builder: (ctx, setState) => strip(
        anchor: 5,
        count: 40,
        heightOf: heightOf,
        centerKey: centerKey,
        controller: controller,
      ),
    ));
    expect(tester.getTopLeft(find.text('page 5')).dy, 0);
    final before = controller.position.pixels;

    // Those pages decode and quadruple in height.
    decoded = true;
    await tester.pumpWidget(StatefulBuilder(
      builder: (ctx, setState) => strip(
        anchor: 5,
        count: 40,
        heightOf: heightOf,
        centerKey: centerKey,
        controller: controller,
      ),
    ));
    await tester.pump();

    expect(controller.position.pixels, before);
    expect(
      tester.getTopLeft(find.text('page 5')).dy,
      0,
      reason: 'growth above the anchor extends into negative offsets',
    );
  });

  testWidgets('scrolling up past the anchor still reaches page 0',
      (tester) async {
    final centerKey = GlobalKey();
    final controller = ScrollController();
    await tester.pumpWidget(strip(
      anchor: 5,
      count: 40,
      heightOf: (_) => 400,
      centerKey: centerKey,
      controller: controller,
    ));

    expect(controller.position.minScrollExtent, -2000);
    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pump();
    expect(tester.getTopLeft(find.text('page 0')).dy, 0);
  });
}
