import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/presentation/common/app_route_observer.dart';

/// Tide, History and the Library grid drop their database subscriptions while
/// nobody can see them. Three things have to hold for that to be safe, and all
/// three are easy to break from a distance:
///
///   * the two ways of being hidden (covered by a route, off-tab) both count,
///     and either one alone is enough;
///   * a screen with no [TabVisibility] above it is NOT hidden — otherwise a
///     screen used outside the shell would silently show nothing;
///   * a tab that has never been shown is left alone, so the shell's
///     post-launch pre-warm still primes its queries.
void main() {
  testWidgets('covering a screen suspends it, popping back resumes it',
      (tester) async {
    final log = <bool>[];
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: _Screen(log: log),
    ));
    expect(log, [true]);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('reader')),
    ));
    await tester.pumpAndSettle();
    expect(log, [true, false]);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(log, [true, false, true]);
  });

  testWidgets('a screen with no tab shell above it is never off-tab',
      (tester) async {
    final log = <bool>[];
    await tester.pumpWidget(MaterialApp(home: _Screen(log: log)));
    expect(log, [true]);
    expect(tester.state<_ScreenState>(find.byType(_Screen)).watching, isTrue);
  });

  testWidgets('a tab that has been shown suspends once it goes off-screen',
      (tester) async {
    final log = <bool>[];
    var visible = true;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return TabVisibility(visible: visible, child: _Screen(log: log));
      }),
    ));
    expect(log, [true]);

    rebuild(() => visible = false);
    await tester.pump();
    expect(log, [true, false]);

    rebuild(() => visible = true);
    await tester.pump();
    expect(log, [true, false, true]);
  });

  testWidgets('a tab that has never been shown is left running to prime',
      (tester) async {
    // The shell builds unvisited tabs during idle so their first query is
    // already paid when you first tap across. Suspending them on sight would
    // undo exactly that.
    final log = <bool>[];
    var visible = false;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return TabVisibility(visible: visible, child: _Screen(log: log));
      }),
    ));
    expect(log, [true], reason: 'primed even though off-tab');

    // Shown for the first time — still watching, nothing changes.
    rebuild(() => visible = true);
    await tester.pump();
    expect(log, [true]);

    // Now that it has been seen, leaving suspends it.
    rebuild(() => visible = false);
    await tester.pump();
    expect(log, [true, false]);
  });

  testWidgets('being covered suspends an on-screen tab too', (tester) async {
    final log = <bool>[];
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: const TabVisibility(visible: true, child: SizedBox()),
    ));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: TabVisibility(visible: true, child: _Screen(log: log)),
    ));
    expect(log, [true]);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('details')),
    ));
    await tester.pumpAndSettle();
    expect(log, [true, false]);
  });

  testWidgets('a suspended screen keeps showing what it last had',
      (tester) async {
    // The whole point of dropping the stream rather than the data: coming
    // back from the reader must not flash a spinner over the list you left.
    final controller = StreamController<String>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: _Screen(log: [], source: () => controller.stream),
    ));
    controller.add('Solo Leveling');
    await tester.pump();
    expect(find.text('Solo Leveling'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('reader')),
    ));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Solo Leveling'), findsOneWidget);
  });
}

class _Screen extends StatefulWidget {
  const _Screen({required this.log, this.source});

  /// One entry per flip of `watching`, starting with its initial value.
  final List<bool> log;
  final Stream<String> Function()? source;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> with SuspendsWhileHidden {
  Stream<String>? _stream;

  @override
  void initState() {
    super.initState();
    widget.log.add(watching);
    _sync();
  }

  void _sync() => _stream = watching ? widget.source?.call() : null;

  @override
  void onWatchingChanged() {
    widget.log.add(watching);
    _sync();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<String>(
          stream: _stream,
          builder: (context, snap) => Text(snap.data ?? 'nothing yet'),
        ),
      );
}
