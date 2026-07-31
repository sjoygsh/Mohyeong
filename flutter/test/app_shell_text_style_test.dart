import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/main.dart';

/// WidgetsApp's fallback DefaultTextStyle draws text with a double YELLOW
/// underline wherever no Material sits above it. `TideText.*` sets colour,
/// size and weight but never `decoration`, so the merge let exactly that one
/// part through — the bars showed on the splash veil and under every toast,
/// which are inserted into the ROOT overlay.
///
/// [buildAppShell] installs the floor above the navigator, which is what
/// makes one fix cover every route AND the overlay. These pin the two places
/// it was actually missing, plus the rule that Material still wins.
void main() {
  Widget host({
    required void Function(BuildContext) onSibling,
    required void Function(BuildContext) onRootOverlay,
    required void Function(BuildContext) onScaffold,
  }) {
    return MaterialApp(
      builder: (context, child) => buildAppShell(
        context,
        Stack(
          children: [
            Builder(builder: (c) {
              onSibling(c);
              return const SizedBox();
            }),
            if (child != null) Positioned.fill(child: child),
          ],
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Builder(builder: (c) {
            onScaffold(c);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Overlay.of(c, rootOverlay: true).insert(
                OverlayEntry(builder: (oc) {
                  onRootOverlay(oc);
                  return const SizedBox();
                }),
              );
            });
            return const SizedBox();
          }),
        ),
      ),
    );
  }

  testWidgets('no subtree inherits the underlined fallback', (tester) async {
    TextStyle? sibling, overlay, scaffold;
    await tester.pumpWidget(host(
      onSibling: (c) => sibling = DefaultTextStyle.of(c).style,
      onRootOverlay: (c) => overlay = DefaultTextStyle.of(c).style,
      onScaffold: (c) => scaffold = DefaultTextStyle.of(c).style,
    ));
    await tester.pump();
    await tester.pump();

    // Outside any Material — these are where the bars actually appeared.
    expect(sibling!.decoration, TextDecoration.none,
        reason: 'splash veil / builder siblings');
    expect(overlay!.decoration, TextDecoration.none, reason: 'toasts');
    // And not the fallback's other giveaways.
    expect(sibling!.fontSize, isNot(48.0));

    // Material still owns the text style inside a route; the floor must not
    // have flattened screens to one style.
    expect(scaffold!.decoration, anyOf(isNull, TextDecoration.none));
  });

  testWidgets('a bare Text under the shell renders undecorated',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => buildAppShell(context, child),
        home: const Text('Mohyeong'),
      ),
    );
    await tester.pump();

    final text = tester.widget<Text>(find.text('Mohyeong'));
    final style = DefaultTextStyle.of(tester.element(find.text('Mohyeong')))
        .style
        .merge(text.style);
    expect(style.decoration, TextDecoration.none);
  });
}
