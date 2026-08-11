import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/source/page_fetch_queue.dart';

/// Pins the scheduling contract [PageFetchQueue] exists for: with one download
/// slot, the page nearest the read position goes next. Before this, reader
/// pages went straight at the cache manager's ten-wide FIFO pool, so the page
/// under your thumb waited behind every page you had already scrolled past.
void main() {
  const pages = <String>[
    'p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9',
  ];

  /// Let every pending microtask and completed gate settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    PageFetchQueue.resetForTest();
    PageFetchQueue.openChapter(pages);
  });

  tearDown(PageFetchQueue.resetForTest);

  /// Starts a queued fetch that records when it begins and blocks on [gate].
  Future<void> start(String url, List<String> log, Completer<void> gate) =>
      PageFetchQueue.run(url, () async {
        log.add(url);
        await gate.future;
      });

  test('a freed slot goes to the waiting page nearest the read position',
      () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p0', 'p2', 'p5', 'p8']) url: Completer<void>(),
    };

    // p0 is the page being read, so it holds the RESERVED lane for the whole
    // test and leaves the general lane — the one whose ordering this pins —
    // behaving exactly as it did when there was only one.
    unawaited(start('p0', log, gates['p0']!));
    await settle();
    // The general lane is taken by whichever of these arrives first, so these
    // three queue up behind it — deliberately not in reading order, the way a
    // fling's mounts and read-aheads arrive.
    unawaited(start('p8', log, gates['p8']!));
    unawaited(start('p2', log, gates['p2']!));
    unawaited(start('p5', log, gates['p5']!));
    await settle();
    expect(log, ['p0', 'p8'], reason: 'one reserved lane, one general lane');

    // Reader has landed on page 2.
    PageFetchQueue.focus(2);

    gates['p8']!.complete();
    await settle();
    expect(log.last, 'p2', reason: 'the page being read wins the free slot');

    gates['p2']!.complete();
    await settle();
    expect(log.last, 'p5', reason: 'then the nearest page ahead');

    gates['p5']!.complete();
    gates['p0']!.complete();
    await settle();
    expect(log, ['p0', 'p8', 'p2', 'p5']);
  });

  test('a page ahead of the reader outranks an equally close page behind it',
      () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p0', 'p4', 'p6']) url: Completer<void>(),
    };

    unawaited(start('p0', log, gates['p0']!));
    await settle();
    unawaited(start('p4', log, gates['p4']!));
    unawaited(start('p6', log, gates['p6']!));
    await settle();

    PageFetchQueue.focus(5);
    gates['p0']!.complete();
    await settle();
    // p4 and p6 are both one page away; Mihon only ever preloads forward.
    expect(log.last, 'p6');

    gates['p6']!.complete();
    gates['p4']!.complete();
    await settle();
  });

  test('URLs outside the open chapter never queue behind pages', () async {
    final log = <String>[];
    final pageGate = Completer<void>();

    unawaited(start('p0', log, pageGate));
    await settle();
    expect(PageFetchQueue.activeForTest, 1);

    // A library cover loading behind the reader must not wait on a page.
    var coverRan = false;
    unawaited(PageFetchQueue.run('https://example.com/cover.jpg', () async {
      coverRan = true;
    }));
    await settle();
    expect(coverRan, isTrue);
    expect(PageFetchQueue.waitingForTest, 0);

    pageGate.complete();
    await settle();
  });

  test('a hung fetch releases its slot instead of stalling the chapter',
      () async {
    PageFetchQueue.slotWatchdog = const Duration(milliseconds: 20);

    final log = <String>[];
    final hung = Completer<void>();
    final next = Completer<void>();

    // Far from the read position, so both of these compete for the general
    // lane rather than one of them taking the reserved one.
    PageFetchQueue.focus(9);
    unawaited(start('p0', log, hung));
    await settle();
    unawaited(start('p1', log, next));
    await settle();
    expect(log, ['p0'], reason: 'p1 is waiting on the general lane');

    // p0 never completes. The watchdog hands the slot on anyway.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(log, ['p0', 'p1']);

    next.complete();
    hung.complete();
    await settle();
  });

  test('reading backwards preloads backwards', () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p9', 'p3', 'p7']) url: Completer<void>(),
    };

    // Arrive at p5 having come DOWN from p8 — the reader is travelling up.
    PageFetchQueue.focus(8);
    PageFetchQueue.focus(5);

    // Occupies the general lane; far enough away that nothing here is
    // eligible for the reserved one, so this is purely about ordering.
    unawaited(start('p9', log, gates['p9']!));
    await settle();
    // p7 is as far from the read position as p3, but it is behind the
    // direction of travel. Under the old fixed forward bias p7 won this.
    unawaited(start('p7', log, gates['p7']!));
    unawaited(start('p3', log, gates['p3']!));
    await settle();
    expect(log, ['p9'], reason: 'both are waiting on the general lane');

    gates['p9']!.complete();
    await settle();
    expect(log.last, 'p3', reason: 'the page about to come on screen wins');

    gates['p3']!.complete();
    gates['p7']!.complete();
    await settle();
  });

  test('scrolling forward is unaffected by the direction bias', () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p1', 'p3', 'p7']) url: Completer<void>(),
    };

    PageFetchQueue.focus(2);
    PageFetchQueue.focus(5);

    unawaited(start('p1', log, gates['p1']!));
    await settle();
    unawaited(start('p3', log, gates['p3']!));
    unawaited(start('p7', log, gates['p7']!));
    await settle();

    gates['p1']!.complete();
    await settle();
    expect(log.last, 'p7');

    gates['p3']!.complete();
    gates['p7']!.complete();
    await settle();
  });

  test('the page being read gets its own slot instead of queueing behind a '
      'preload', () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p6', 'p1']) url: Completer<void>(),
    };

    // A preload four pages out takes the general slot first.
    PageFetchQueue.focus(2);
    unawaited(start('p6', log, gates['p6']!));
    await settle();
    expect(log, ['p6']);

    // The page now under the reader must not wait for that download: a page
    // measures seconds, and waiting one out is most of "why is this blank".
    PageFetchQueue.focus(1);
    unawaited(start('p1', log, gates['p1']!));
    await settle();
    expect(log, ['p6', 'p1'], reason: 'the reserved slot took it straight away');

    gates['p6']!.complete();
    gates['p1']!.complete();
    await settle();
    expect(PageFetchQueue.activeForTest, 0, reason: 'both slots released');
  });

  test('preloads never take the reserved slot', () async {
    final log = <String>[];
    final gates = {
      for (final url in ['p0', 'p5', 'p6']) url: Completer<void>(),
    };

    PageFetchQueue.focus(0);
    unawaited(start('p0', log, gates['p0']!));
    await settle();
    unawaited(start('p5', log, gates['p5']!));
    unawaited(start('p6', log, gates['p6']!));
    await settle();
    // p0 holds the reserved slot, p5 the general one; p6 waits. If preloads
    // could use the reserved lane this would be three at once.
    expect(log, ['p0', 'p5']);

    gates['p0']!.complete();
    gates['p5']!.complete();
    gates['p6']!.complete();
    await settle();
  });

  test('opening another chapter re-bases the ordering', () async {
    PageFetchQueue.openChapter(const ['q0', 'q1', 'q2']);
    final log = <String>[];
    final gates = {
      for (final url in ['q0', 'q1', 'q2']) url: Completer<void>(),
    };

    unawaited(start('q0', log, gates['q0']!));
    await settle();
    unawaited(start('q2', log, gates['q2']!));
    unawaited(start('q1', log, gates['q1']!));
    await settle();

    gates['q0']!.complete();
    await settle();
    expect(log.last, 'q1');

    gates['q1']!.complete();
    gates['q2']!.complete();
    await settle();
  });
}
