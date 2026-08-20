import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/reader/strip_tail_action.dart';

/// Read-ahead keeps a fixed four pages of lead, and inside a chapter that lead
/// is always warm. At a chapter boundary it was not: nothing of the next
/// chapter could be fetched until its page list arrived — a network round trip
/// the reader never pays mid-chapter — so the lead was rebuilt from zero and
/// the first pages of the new chapter sat there loading. The page list is now
/// fetched on a wider window than the append that consumes it.
void main() {
  StripTailAction at(int pagesRemaining, {bool last = true}) =>
      stripTailAction(pagesRemaining: pagesRemaining, isLastLoadedChapter: last);

  test('deep inside a chapter, nothing happens', () {
    expect(at(40), StripTailAction.none);
    expect(at(stripPageListPrefetchWithin + 1), StripTailAction.none);
  });

  test('the page list is warmed before the strip grows', () {
    expect(at(stripPageListPrefetchWithin),
        StripTailAction.prefetchNextPageList);
    expect(at(stripAppendWithin + 1), StripTailAction.prefetchNextPageList);
  });

  test('the append takes over near the end, and stays taken over', () {
    expect(at(stripAppendWithin), StripTailAction.appendNext);
    expect(at(1), StripTailAction.appendNext);
    expect(at(0), StripTailAction.appendNext, reason: 'the last page');
  });

  test('the prefetch window is wider than the append window', () {
    // The whole point: the list has to be in hand BEFORE the strip needs it.
    expect(stripPageListPrefetchWithin, greaterThan(stripAppendWithin));
  });

  test('a chapter shorter than the window prefetches from its first page', () {
    // An 8-page chapter never sees pagesRemaining > 8.
    expect(at(7), StripTailAction.prefetchNextPageList);
  });

  test('nothing is pulled in behind a chapter that is not the last', () {
    for (final remaining in [0, 1, stripAppendWithin, 40]) {
      expect(at(remaining, last: false), StripTailAction.none);
    }
  });
}
