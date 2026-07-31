import '../model/chapter.dart';

/// Collapses competing releases of the same chapter down to the scanlator the
/// user ranked highest. 1:1 with the Kotlin fork's
/// `MangaScreenModel.State.Success.processedChapters`.
///
/// [priority] is an order, most preferred first; a scanlator that isn't in it
/// is unranked. Runs AFTER filtering and sorting, on the list the chapter list
/// is about to render — it never touches the database.
///
/// Rules, matching the fork:
/// - an empty [priority] returns [chapters] untouched, so a manga nobody has
///   ranked keeps every release;
/// - chapters are grouped by chapter number, and a group of one is kept as-is;
/// - a group in which NO chapter has a ranked scanlator falls through whole —
///   ranking one scanlator must not silently hide releases by scanlators the
///   user never expressed an opinion about;
/// - otherwise the single highest-ranked chapter wins the number.
///
/// **Divergence from the fork, deliberate.** Kotlin groups by chapter number
/// without excluding unrecognised ones, so every chapter whose number failed
/// to parse lands in ONE group keyed on the same sentinel. The moment any of
/// them is by a ranked scanlator, that group collapses to a single row and the
/// rest of the manga's extras/specials disappear — which contradicts the
/// fork's own comment that "unrecognized numbers ... fall through unchanged".
/// Unrecognised chapters are passed through untouched here, because a number
/// that was never recognised is not evidence that two chapters are the same
/// chapter. Same failure mode as the merge's filter-after-dedupe bug: a row
/// the user can still reach nowhere else quietly leaves the list.
List<Chapter> applyScanlatorPriority(
  List<Chapter> chapters,
  List<String> priority,
) {
  if (priority.isEmpty || chapters.isEmpty) return chapters;

  final rank = <String, int>{};
  for (var i = 0; i < priority.length; i++) {
    // First occurrence wins, so a duplicated name can't shadow its own rank.
    rank.putIfAbsent(priority[i], () => i);
  }

  // Insertion-ordered, so groups come back out in the order the sorted list
  // first mentioned each number and the rendered order is preserved.
  final groups = <double, List<Chapter>>{};
  final passthrough = <Chapter>[];
  for (final c in chapters) {
    if (!c.isRecognizedNumber) {
      passthrough.add(c);
      continue;
    }
    (groups[c.chapterNumber] ??= <Chapter>[]).add(c);
  }

  // Ids, not Chapter instances: this must not depend on whether Chapter
  // carries value equality.
  final kept = <int>{};
  for (final group in groups.values) {
    if (group.length == 1) {
      kept.add(group.first.id);
      continue;
    }
    Chapter? winner;
    var winnerRank = 1 << 30;
    for (final c in group) {
      final scanlator = c.scanlator;
      final r = scanlator == null ? null : rank[scanlator];
      if (r != null && r < winnerRank) {
        winner = c;
        winnerRank = r;
      }
    }
    if (winner == null) {
      kept.addAll(group.map((c) => c.id));
    } else {
      kept.add(winner.id);
    }
  }
  kept.addAll(passthrough.map((c) => c.id));

  // Rebuild in the caller's order rather than group order: the list arrives
  // sorted, and volume headers / "missing N chapters" separators are computed
  // downstream from adjacency.
  return [
    for (final c in chapters)
      if (kept.contains(c.id)) c,
  ];
}
