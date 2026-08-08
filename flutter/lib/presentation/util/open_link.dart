/// Opening a web address, the one way.
///
/// Six screens used to call `launchUrl` bare from an `onTap`, unawaited. That
/// is worse than it looks: `launchUrl` THROWS when nothing on the device can
/// handle the intent, and an unawaited future has nobody to catch it, so the
/// failure went to the unhandled-error zone and the tap simply did nothing.
/// A help button that silently does nothing is indistinguishable from a help
/// button that is broken, which is exactly what a user reports it as.
///
/// Two more spellings existed alongside it: `canLaunchUrl` first (onboarding),
/// and inspecting the returned bool (manga details). Three ways to do one
/// thing, only one of which told the user anything. This is that one.
library;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tide/tide.dart';

/// Where the docs live.
const String docsHome = 'https://sjoygsh.github.io/Mohyeong/';

/// The docs page, optionally at [anchor].
///
/// Every help button in the app goes through this, so a section that gets
/// renamed is one edit and a `grep helpUrl` lists every link the app makes.
/// Anchors used here MUST exist in `docs/help.html`; a link to a missing one
/// dumps the reader at the top of the page with no sign anything went wrong,
/// which is how Upcoming's help button spent its life pointing at Getting
/// Started.
String helpUrl([String? anchor]) =>
    anchor == null ? '${docsHome}help.html' : '${docsHome}help.html#$anchor';

/// Opens [url] in the browser, saying so if it cannot.
///
/// Capture nothing and pass [context] straight in: the toast overlay is
/// resolved BEFORE the await, which is the whole discipline [TideToast.of]
/// exists to enforce.
Future<void> openLink(BuildContext context, String url) async {
  final toast = TideToast.of(context);
  final uri = Uri.tryParse(url);
  if (uri == null) {
    toast.show('That address is not valid.');
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    // `false` is the launcher reporting no handler without throwing; both
    // outcomes mean the same thing to the person who tapped.
    if (!ok) toast.show('No app on this device can open links.');
  } catch (_) {
    toast.show('Could not open the browser.');
  }
}
