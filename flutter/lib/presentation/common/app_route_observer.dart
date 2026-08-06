import 'package:flutter/widgets.dart';

/// The app's single [RouteObserver], registered on the [MaterialApp]'s
/// navigator.
///
/// It exists so a screen can know it has been covered by another one. Flutter
/// keeps a covered route's State alive and its streams subscribed, which is
/// usually what you want — but the series screen watches its manga's whole
/// chapter list, and the reader that covers it writes `last_page_read` as you
/// turn pages. Drift invalidates per table, so every one of those writes made
/// the screen underneath re-read and re-merge every chapter of the series,
/// for a view nobody could see. A screen that opts in via [RouteAware] can
/// drop that subscription while it is covered and take it back on return.
/// Typed to [PageRoute] on purpose: only a full screen counts as covering
/// one. A bottom sheet or dialog over a screen is not the screen going away,
/// and a `RouteObserver<ModalRoute>` would report those too — a sheet you can
/// mark chapters from would have suspended the list behind it.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Tells the subtree whether the tab it sits in is the one on screen.
///
/// The shell's [IndexedStack] keeps every tab it has built alive, so a tab
/// widget cannot tell from its own state whether anyone can see it. The shell
/// wraps each tab in one of these; [SuspendsWhileHidden] reads it.
///
/// The shell is the one that knows, so the shell is what says so — a screen
/// comparing its own hardcoded index against the selected tab would be wrong
/// the moment the bar is reordered, and would report itself invisible
/// anywhere it is mounted outside the shell. Hence the default: no
/// [TabVisibility] above you means nothing is hiding you.
class TabVisibility extends InheritedWidget {
  const TabVisibility({required this.visible, required super.child, super.key});

  final bool visible;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabVisibility>()?.visible ??
      true;

  @override
  bool updateShouldNotify(TabVisibility oldWidget) =>
      oldWidget.visible != visible;
}

/// Keeps a screen's database subscriptions alive only while the screen can
/// actually be seen.
///
/// There are two ways for a live screen to be invisible, and both of them
/// happen constantly here. A route can be COVERED by another one — the whole
/// shell sits under the series screen and the reader for as long as you read.
/// And a tab can be OFF-SCREEN: the shell's [IndexedStack] keeps every tab it
/// has built alive so scroll positions survive, so Tide and History go on
/// watching the database while you are somewhere else entirely.
///
/// That costs real work rather than nothing, because drift invalidates query
/// streams per TABLE. A page turn writes `last_page_read`, which touches
/// `chapters`, which re-runs Tide's whole-library aggregate, its updates join
/// and History's recent-reads join, re-maps every row into fresh objects, and
/// hands each screen a new list — new identity, so their memoised sort and
/// grouping miss too. Measured at 300 favourites x 60 chapters: ~23ms of that
/// per page turn, every 600ms while reading, for three screens nobody is
/// looking at.
///
/// Mix in, keep the streams in fields, and in [onWatchingChanged] rebuild
/// them when [watching] is true / drop them to null when it is false. Do NOT
/// call `setState` there — the mixin schedules the rebuild itself, since one
/// of the two triggers arrives mid-build and a second one would assert. A
/// [StreamBuilder] handed a null stream keeps the data it already had, so a
/// resumed screen shows what you left and quietly refreshes — never a spinner.
mixin SuspendsWhileHidden<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool _covered = false;
  bool _offTab = false;

  /// Whether this screen has ever actually been on screen.
  ///
  /// The shell pre-warms its unvisited tabs during post-launch idle precisely
  /// so their first build AND their first query are already paid when you
  /// first tap across. Suspending an off-tab screen unconditionally would
  /// take that back, so a tab that has never been shown is left to prime.
  /// After it has been seen once, being off-tab suspends it like anything
  /// else.
  bool _shownOnce = false;

  /// Whether this screen should be watching the database right now.
  bool get watching => !_covered && (!_offTab || !_shownOnce);

  /// Swap the screen's streams in or out to match [watching]. Called when,
  /// and only when, [watching] flips. Plain field assignment — see above.
  void onWatchingChanged();

  /// Applies a change and, if it flipped [watching], swaps the streams.
  ///
  /// [schedulesRebuild] says whether the caller still needs one: a route
  /// callback fires between frames and does, while [didChangeDependencies]
  /// runs inside a build that is about to happen anyway and must not ask for
  /// a second.
  void _update(void Function() change, {required bool schedulesRebuild}) {
    final was = watching;
    change();
    if (watching == was) return;
    onWatchingChanged();
    if (schedulesRebuild) setState(() {});
  }

  void _setCovered(bool covered) =>
      _update(() => _covered = covered, schedulesRebuild: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
    final visible = TabVisibility.of(context);
    // Both inside the closure: read together, they are one transition. Marking
    // _shownOnce first would make the "before" reading of [watching] false for
    // a tab that was only ever primed, and the first sight of it would look
    // like a resume.
    _update(() {
      if (visible) _shownOnce = true;
      _offTab = !visible;
    }, schedulesRebuild: false);
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  @override
  void didPush() {}

  @override
  void didPop() {}

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }
}
