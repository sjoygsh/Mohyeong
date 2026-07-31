import '../../../data/util/stream_combine.dart';
import '../../manga/model/manga.dart';
import '../model/chapter.dart';
import 'merge_linked_chapters.dart';

/// One emission of the merged chapter stream: the display list and its
/// cluster index, plus the linked manga each merged row belongs to.
class ClusterChapters {
  const ClusterChapters(this.merged, this.mangaById);

  final MergedChapters merged;

  /// Linked manga by id, empty when nothing is linked. A merged row can come
  /// from a mirror, and its pages, downloads and per-source headers all live
  /// under THAT manga rather than the screen's primary.
  final Map<int, Manga> mangaById;
}

/// The details screen's chapter stream: this manga's chapters merged with
/// every linked source's, re-merging whenever the cluster membership or the
/// excluded-scanlator set changes.
///
/// Lives here rather than inline in the screen so it can be tested without
/// mounting the screen — it is the piece that decides what the chapter list
/// contains, and it was previously reachable only through the widget tree.
///
/// [switchMap] re-subscribes when the cluster itself changes (a title linked
/// or unlinked), so the list follows membership without a screen rebuild.
/// With nothing linked this is the plain per-manga watch it has always been,
/// plus one cheap subscription to the (usually empty) links table.
Stream<ClusterChapters> watchClusterChapters({
  required int primaryMangaId,
  required Stream<List<Manga>> Function(int mangaId) watchLinked,
  required Stream<List<Chapter>> Function(int mangaId) watchChapters,
  required Stream<Set<String>> Function(int mangaId) watchExcludedScanlators,
}) {
  return switchMap(watchLinked(primaryMangaId), (linked) {
    final primary = watchChapters(primaryMangaId);
    if (linked.isEmpty) {
      return primary.map(
        (chapters) => ClusterChapters(
          mergeLinkedChapters(
            primaryMangaId: primaryMangaId,
            primaryChapters: chapters,
            linked: const [],
          ),
          const {},
        ),
      );
    }
    // The excluded set rides along because the merge has to drop those rows
    // BEFORE it dedupes — see [mergeLinkedChapters]. Filtering only at render
    // time made a chapter disappear whenever the copy that won its number
    // happened to be the excluded one.
    return combineLatest2(
      combineLatestList<List<Chapter>>([
        primary,
        for (final lm in linked) watchChapters(lm.id),
      ]),
      watchExcludedScanlators(primaryMangaId),
      (List<List<Chapter>> lists, Set<String> excluded) => ClusterChapters(
        mergeLinkedChapters(
          primaryMangaId: primaryMangaId,
          primaryChapters: lists.first,
          linked: lists.sublist(1),
          excludedScanlators: excluded,
        ),
        {for (final lm in linked) lm.id: lm},
      ),
    );
  });
}
