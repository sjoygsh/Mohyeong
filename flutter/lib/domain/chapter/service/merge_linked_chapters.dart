import '../model/chapter.dart';

/// The display list for a linked cluster plus the index that keeps read
/// state shared across it.
class MergedChapters {
  const MergedChapters({required this.chapters, required this.byNumber});

  /// What the chapter list renders: one row per recognised chapter number,
  /// followed by every unrecognised chapter.
  final List<Chapter> chapters;

  /// Recognised chapter number → every chapter carrying it, across the
  /// primary and all linked sources. Marking one read marks them all, which
  /// is the whole point of a cluster: the same chapter read on a mirror
  /// shouldn't come back unread under the primary.
  final Map<double, List<Chapter>> byNumber;

  static const empty = MergedChapters(chapters: [], byNumber: {});
}

/// Builds the merged chapter list for a linked cluster. 1:1 with the Kotlin
/// fork's `MangaScreenModel.mergeChapters`.
///
/// Dedupe is by recognised chapter number. **The primary always wins**; among
/// linked sources the first one to claim a number wins, which is stable
/// because the repository returns the cluster in priority order. Chapters
/// whose number was never recognised (`chapterNumber < 0`) can't be deduped
/// at all, so every one of them passes through.
///
/// `sourceOrder` is reassigned across the merged set. Each source numbers its
/// own chapters independently — newest is 0 everywhere — so sorting the
/// combined list by the stored `sourceOrder` would interleave three sources
/// nonsensically. Resequencing by chapter number descending makes the
/// existing "by source order" sort produce the right merged order. The
/// mutation is on copies that only reach the UI; DB rows are untouched.
///
/// **Divergence from the fork, deliberate:** Kotlin runs this even when
/// nothing is linked, which silently rewrites `sourceOrder` for every manga
/// in the app. Here [linked] being empty returns the primary list verbatim,
/// so a manga with no cluster keeps exactly the ordering it has today and
/// this feature stays additive. With no linked chapters there is nothing to
/// dedupe, so the only thing that resequencing could change is the ordering
/// of a source that lists its chapters out of numeric order — which is the
/// source's own choice to respect.
MergedChapters mergeLinkedChapters({
  required int primaryMangaId,
  required List<Chapter> primaryChapters,
  required List<List<Chapter>> linked,
}) {
  if (linked.every((l) => l.isEmpty)) {
    // No index either: with nothing to share state with, expanding a
    // selection is the identity, and this runs on every chapter emission for
    // every manga in the app.
    return MergedChapters(chapters: primaryChapters, byNumber: const {});
  }

  // Insertion-ordered by construction, which is what makes "first writer
  // wins" stable across linked sources.
  final winners = <double, Chapter>{};
  final unrecognized = <Chapter>[];
  final byNumber = <double, List<Chapter>>{};

  void ingest(List<Chapter> chapters, {required bool isPrimary}) {
    for (final c in chapters) {
      if (!c.isRecognizedNumber) {
        unrecognized.add(c);
        continue;
      }
      (byNumber[c.chapterNumber] ??= <Chapter>[]).add(c);
      final existing = winners[c.chapterNumber];
      if (existing == null ||
          (isPrimary && existing.mangaId != primaryMangaId)) {
        winners[c.chapterNumber] = c;
      }
    }
  }

  ingest(primaryChapters, isPrimary: true);
  for (final chapters in linked) {
    ingest(chapters, isPrimary: false);
  }

  final sorted = winners.values.toList(growable: false)
    ..sort((a, b) => b.chapterNumber.compareTo(a.chapterNumber));
  final merged = <Chapter>[
    for (final (i, c) in sorted.indexed) c.copyWith(sourceOrder: i),
    for (final (i, c) in unrecognized.indexed)
      c.copyWith(sourceOrder: sorted.length + i),
  ];
  return MergedChapters(chapters: merged, byNumber: byNumber);
}

/// Expands a user selection so an action taken on a merged row lands on every
/// copy of that chapter in the cluster. Kotlin's `markChaptersRead` does this
/// inline; it is pulled out here because the Flutter screen needs it from
/// several call sites (row tap, bulk action, mark-previous).
///
/// Chapters with an unrecognised number expand to themselves — there is no
/// number to match them on.
List<Chapter> expandAcrossCluster(
  Iterable<Chapter> selection,
  Map<double, List<Chapter>> byNumber,
) {
  final out = <Chapter>[];
  final seen = <int>{};
  for (final c in selection) {
    final matches =
        c.isRecognizedNumber ? (byNumber[c.chapterNumber] ?? [c]) : [c];
    for (final m in matches) {
      if (seen.add(m.id)) out.add(m);
    }
  }
  return out;
}
