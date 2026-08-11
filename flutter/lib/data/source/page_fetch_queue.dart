import 'dart:async';

import '../dev/frame_stats.dart';

/// Orders reader page downloads the way Mihon's `HttpPageLoader` does.
///
/// Mihon runs **one** download at a time out of a `PriorityBlockingQueue`, and
/// the page you are actually looking at outranks the four it preloads ahead of
/// you. We had neither: every mounted page and every read-ahead went straight
/// at `flutter_cache_manager`, which runs up to ten concurrent fetches and
/// serves the rest strictly FIFO. Scrolling fast enqueued a dozen multi-megabyte
/// webtoon pages, so the page under your thumb waited behind pages you had
/// already flown past, ten downloads split the bandwidth and none of them
/// finished — the deeper into a chapter you got the worse it was, and standing
/// still for a minute drained the backlog and "fixed" it.
///
/// So: reader pages queue here, and a freed slot goes to whichever waiting page
/// is nearest the read position. A fling re-points [focus] and the pages left
/// behind sink on their own — no cancellation needed, they simply stop winning.
///
/// URLs that were never registered by [openChapter] — covers, browse grids,
/// anything outside the reader — bypass this entirely and keep the cache
/// manager's own wider pool. Only pages compete for the reader's slot.
abstract final class PageFetchQueue {
  /// Mihon's `HttpPageLoader` consumes its queue with a single worker. Matching
  /// it is the point: the win here is that one page finishes *now* rather than
  /// eight crawling in together.
  static const int maxConcurrent = 1;

  /// One further slot, reserved for the page at (or next to) the read
  /// position — never usable by a preload.
  ///
  /// The single slot was right about bandwidth and wrong about latency. A
  /// page on this device measures 1.5-2.7s to download, so a page arriving
  /// at the queue behind an in-flight preload waits a whole download before
  /// it starts: measured on device, the page ON SCREEN waited 4.7s for the
  /// slot and then took 2.7s to fetch — seven seconds to show a page, and
  /// two thirds of that was us, not the network. Preloads waiting ~7s is the
  /// design working; the page under your eyes waiting that long is not.
  ///
  /// So the ordering stays exactly as it was — preloads still go one at a
  /// time, nearest first — and the page being read gets a lane of its own.
  /// This is not a walk back towards the ten-wide FIFO this replaced: that
  /// had no ordering at all, so the page under your thumb queued behind
  /// pages you had already scrolled past. Here at most one preload and one
  /// on-screen page ever share the link.
  static const int maxPriority = 1;

  /// A page this close to [_focus] is one the reader is looking at or about
  /// to, and may use the reserved slot.
  static const int priorityWithin = 1;

  /// A slot is never held longer than this even if the fetch is still running.
  /// With one slot, one hung request would otherwise stall every remaining page
  /// in the chapter — worse than the unbounded fetching this replaces. The
  /// fetch itself is left alone; it just stops blocking the queue.
  static Duration slotWatchdog = const Duration(seconds: 20);

  /// Page URL -> its index in the open chapter. Membership is what marks a URL
  /// as a reader page at all.
  static final Map<String, int> _index = <String, int>{};

  static final List<_Waiter> _waiting = <_Waiter>[];

  static int _active = 0;
  static int _priorityActive = 0;

  /// Index of the page being read; the ordering key for everything waiting.
  static int _focus = 0;

  /// Registers the open chapter's pages in reading order. Later duplicates of
  /// the same URL keep the first (lowest) index — a repeated image should be
  /// scheduled by its earliest appearance.
  static void openChapter(Iterable<String?> urls) {
    _index.clear();
    var i = 0;
    for (final url in urls) {
      if (url != null && url.isNotEmpty) {
        _index.putIfAbsent(url, () => i);
      }
      i++;
    }
    _focus = 0;
    _direction = 1;
  }

  /// Leaving the reader. In-flight fetches finish on their own; they just stop
  /// being prioritised as pages.
  static void close() {
    _index.clear();
    _focus = 0;
  }

  /// Which way the reader is travelling: +1 down the chapter, -1 back up it.
  /// Preloading is biased this way rather than unconditionally forward.
  static int _direction = 1;

  /// The page currently being read. Costs nothing to call per scroll update.
  static void focus(int index) {
    if (index != _focus) _direction = index > _focus ? 1 : -1;
    _focus = index;
  }

  /// Runs [body] under the reader's download slot when [url] is a page of the
  /// open chapter, and directly otherwise.
  static Future<T> run<T>(String url, Future<T> Function() body) async {
    final index = _index[url];
    if (index == null) return body();

    final queuedAt = DateTime.now().microsecondsSinceEpoch;
    // True while this fetch holds the reserved on-screen slot rather than the
    // general one; it has to be remembered, because by the time the fetch
    // finishes the reader has usually moved and the test would no longer
    // give the same answer — releasing the wrong counter would leak a slot.
    var priority = false;
    if (_isPriority(index) && _priorityActive < maxPriority) {
      priority = true;
      _priorityActive++;
    } else if (_active < maxConcurrent) {
      _active++;
    } else {
      final waiter = _Waiter(index);
      _waiting.add(waiter);
      // [_pump] counts the slot when it releases us, so we must not re-count.
      priority = await waiter.gate.future;
    }
    // Split the two halves of "this page took forever": time spent waiting
    // for the single slot, and time spent actually fetching. Only the first
    // is ours to fix.
    final startedAt = DateTime.now().microsecondsSinceEpoch;
    final waited = (startedAt - queuedAt) ~/ 1000;
    // Bucketed by how close the page is to the read position AT DEQUEUE. A
    // preload four pages out waiting several seconds is the design working;
    // the page under your eyes waiting that long is the bug. One number for
    // both cannot tell them apart.
    if ((index - _focus).abs() <= 1) {
      FrameStats.max('wait-onscreen-ms', waited);
    } else {
      FrameStats.max('wait-preload-ms', waited);
    }
    FrameStats.count('fetches');

    var released = false;
    void release() {
      if (released) return;
      released = true;
      if (priority) {
        _priorityActive--;
      } else {
        _active--;
      }
      _pump();
    }

    final watchdog = Timer(slotWatchdog, () {
      FrameStats.count('fetch-watchdog-fired');
      release();
    });
    try {
      return await body();
    } finally {
      watchdog.cancel();
      FrameStats.max('fetch-body-ms',
          (DateTime.now().microsecondsSinceEpoch - startedAt) ~/ 1000);
      release();
    }
  }

  /// Whether [index] is close enough to the read position to use the
  /// reserved slot. Evaluated fresh at every acquire and at every pump, so a
  /// page that has become the one being read while it waited can claim it.
  static bool _isPriority(int index) =>
      (index - _focus).abs() <= priorityWithin;

  static void _pump() {
    // Reserved slot first, and only to a waiter that is on screen NOW.
    while (_priorityActive < maxPriority) {
      final best = _bestWaiter(onlyPriority: true);
      if (best < 0) break;
      final waiter = _waiting.removeAt(best);
      _priorityActive++;
      waiter.gate.complete(true);
    }
    while (_active < maxConcurrent) {
      final best = _bestWaiter(onlyPriority: false);
      if (best < 0) break;
      final waiter = _waiting.removeAt(best);
      _active++;
      waiter.gate.complete(false);
    }
  }

  /// Index into [_waiting] of the cheapest waiter, or -1 if none qualifies.
  static int _bestWaiter({required bool onlyPriority}) {
    var best = -1;
    for (var i = 0; i < _waiting.length; i++) {
      if (onlyPriority && !_isPriority(_waiting[i].index)) continue;
      if (best < 0 || _cost(_waiting[i].index) < _cost(_waiting[best].index)) {
        best = i;
      }
    }
    return best;
  }

  /// Scheduling cost of a page: distance from the read position, biased the
  /// way the reader is TRAVELLING. Mihon only ever preloads pages after the
  /// current one, and so did this — a page behind the reader yielded to
  /// anything ahead of it, unconditionally.
  ///
  /// That was right while the strip only grew forward. Now that it also pulls
  /// in the previous chapter, back is a direction you can read in, and a fixed
  /// forward bias serves it as badly as possible: scrolling up, the page about
  /// to come on screen sat at cost 12 while four pages you were moving AWAY
  /// from sat at 1 through 4, and won the single download slot every time.
  /// Reading backwards fetched everything except what you were looking at.
  ///
  /// So the ×8 penalty now falls on going against the travel, whichever way
  /// that is. Scrolling down behaves exactly as before.
  static int _cost(int index) {
    final delta = (index - _focus) * _direction;
    return delta >= 0 ? delta : -delta * 8 + 4;
  }

  /// Test seam: the queue is process-wide static state.
  static void resetForTest() {
    _index.clear();
    _waiting.clear();
    _active = 0;
    _priorityActive = 0;
    _focus = 0;
    _direction = 1;
    slotWatchdog = const Duration(seconds: 20);
  }

  static int get activeForTest => _active + _priorityActive;

  static int get waitingForTest => _waiting.length;
}

class _Waiter {
  _Waiter(this.index);

  final int index;
  /// Completes with whether the slot handed over is the reserved on-screen
  /// one, so the waiter releases the counter it actually took.
  final Completer<bool> gate = Completer<bool>();
}
