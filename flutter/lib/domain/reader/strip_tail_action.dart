/// What the continuous strip should do as the reader nears the end of the last
/// chapter it holds.
///
/// Two distances, not one. The APPEND is the visible growth of the strip and
/// happens late, close to the end; the next chapter's PAGE LIST is fetched
/// well before that. Read-ahead keeps a fixed four pages of lead, and inside a
/// chapter that lead is always warm — at a boundary it is not, because nothing
/// of the next chapter can be fetched until its page list arrives, and that
/// list is a network round trip the reader never pays mid-chapter. Starting it
/// early turns the append into a local hand-off, so the first pages of the new
/// chapter are fetchable the moment the strip grows into them.
library;

enum StripTailAction {
  /// Far enough from the end that nothing is needed yet.
  none,

  /// Warm the next chapter's page list; the strip does not grow.
  prefetchNextPageList,

  /// Pull the next chapter into the strip.
  appendNext,
}

/// Pages from the reader's position to the end of the chapter, at or below
/// which the strip grows.
const int stripAppendWithin = 5;

/// The wider window at which the next chapter's page list starts loading. One
/// cheap request, and having it in hand is what lets read-ahead cross a
/// boundary without stalling. A chapter shorter than this simply prefetches
/// from its first page.
const int stripPageListPrefetchWithin = 12;

/// [pagesRemaining] counts the pages after the current one, so 0 is the last
/// page of the chapter.
StripTailAction stripTailAction({
  required int pagesRemaining,
  required bool isLastLoadedChapter,
}) {
  if (!isLastLoadedChapter) return StripTailAction.none;
  if (pagesRemaining <= stripAppendWithin) return StripTailAction.appendNext;
  if (pagesRemaining <= stripPageListPrefetchWithin) {
    return StripTailAction.prefetchNextPageList;
  }
  return StripTailAction.none;
}
