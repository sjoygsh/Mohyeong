import 'package:flutter/material.dart';

/// Fills a [total]-pixel-tall reservation with [leading] on top and a copy of
/// [mark] centred in every [viewport] below it, so however deep into the
/// reservation the reader is parked there is one within half a screen.
///
/// A long-strip page is two to four screens tall, so anything centred in the
/// whole box — a spinner, a failure line — is usually off-screen, and what the
/// reader shows instead is a screen of nothing. The cells sum to exactly
/// [total]: the reservation is what the continuous viewer's offset↔index maths
/// is built on, and this must not disturb it.
Widget markedDownPage({
  required double total,
  required double viewport,
  Widget? leading,
  Widget? mark,
}) {
  final head = leading ?? (mark == null ? null : Center(child: mark));
  if (!total.isFinite || total <= 0 || viewport <= 0) {
    return SizedBox(
      height: total.isFinite && total > 0 ? total : null,
      child: head,
    );
  }
  final cells = <Widget>[];
  var remaining = total;
  final first = remaining < viewport ? remaining : viewport;
  cells.add(SizedBox(height: first, child: head));
  remaining -= first;
  // Bounded so a wild extent estimate can't spawn an unbounded column.
  while (mark != null && remaining > 1 && cells.length < maxPageMarks) {
    final h = remaining < viewport ? remaining : viewport;
    cells.add(SizedBox(height: h, child: Center(child: mark)));
    remaining -= h;
  }
  if (remaining > 1) cells.add(SizedBox(height: remaining));
  return Column(mainAxisSize: MainAxisSize.min, children: cells);
}

/// Ceiling on the repeats [markedDownPage] lays down. A page's reserved extent
/// is an estimate until its bitmap lands, and an estimate that comes back wild
/// must not spawn an unbounded column.
const int maxPageMarks = 8;

/// A reader page's loading spinner / failure line, repeated once per viewport
/// down whatever box the page occupies (see [markedDownPage]).
///
/// The continuous viewer reserves each page's REAL extent as soon as its
/// aspect ratio is known, and read-ahead now learns that ratio before the slot
/// mounts — so the common case is a correctly-sized, several-screen-tall box
/// whose bitmap has not arrived yet. Its placeholder was a `SizedBox(height:
/// 400)` handed tight page-tall constraints, which centres one spinner a
/// screen or two below the viewport: scrolling onto a page still downloading
/// showed a band of empty reader background with nothing in it and no sign
/// that anything was happening — every few pages, wherever the one-at-a-time
/// download queue had not caught up. The mark tiles instead, so a page that is
/// merely slow says so.
///
/// In the paged viewer the box IS one viewport, which yields a single centred
/// mark — exactly what it showed before.
class PageMark extends StatelessWidget {
  const PageMark({super.key, required this.mark});

  final Widget mark;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (ctx, constraints) => markedDownPage(
        total: constraints.hasBoundedHeight ? constraints.maxHeight : viewport,
        viewport: viewport,
        mark: mark,
      ),
    );
  }
}
