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
