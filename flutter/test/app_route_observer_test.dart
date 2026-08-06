import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/presentation/common/app_route_observer.dart';

/// The series screen drops its chapter subscription while the reader is on
/// top of it, and takes it back on return. That rests on two things being
/// true of [appRouteObserver], both easy to break by widening its type: a
/// full screen pushed over a screen reports as covering it, and a bottom
/// sheet over the same screen does NOT.
void main() {
  late List<String> events;

  Widget harness() => MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: _Watcher(onEvent: events.add),
      );

  setUp(() => events = <String>[]);

  testWidgets('a full screen pushed on top covers, popping uncovers',
      (tester) async {
    await tester.pumpWidget(harness());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('reader')),
    ));
    await tester.pumpAndSettle();
    expect(events, ['covered']);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(events, ['covered', 'uncovered']);
  });

  testWidgets('a route returning a value still covers', (tester) async {
    // The generic argument varies across the app's pushes; PageRoute<dynamic>
    // is what makes them all count.
    await tester.pumpWidget(harness());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    navigator.push(MaterialPageRoute<bool>(
      builder: (_) => const Scaffold(body: Text('picker')),
    ));
    await tester.pumpAndSettle();
    expect(events, ['covered']);
  });

  testWidgets('a bottom sheet over the screen does not cover it',
      (tester) async {
    await tester.pumpWidget(harness());
    final context = tester.element(find.text('watching'));

    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(events, isEmpty);
  });
}

class _Watcher extends StatefulWidget {
  const _Watcher({required this.onEvent});
  final ValueChanged<String> onEvent;

  @override
  State<_Watcher> createState() => _WatcherState();
}

class _WatcherState extends State<_Watcher> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() => widget.onEvent('covered');

  @override
  void didPopNext() => widget.onEvent('uncovered');

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('watching')));
}
