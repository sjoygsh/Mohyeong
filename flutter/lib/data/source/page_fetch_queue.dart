import 'dart:async';

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
  }

  /// Leaving the reader. In-flight fetches finish on their own; they just stop
  /// being prioritised as pages.
  static void close() {
    _index.clear();
    _focus = 0;
  }

  /// The page currently being read. Costs nothing to call per scroll update.
  static void focus(int index) => _focus = index;

  /// Runs [body] under the reader's download slot when [url] is a page of the
  /// open chapter, and directly otherwise.
  static Future<T> run<T>(String url, Future<T> Function() body) async {
    final index = _index[url];
    if (index == null) return body();

    if (_active < maxConcurrent) {
      _active++;
    } else {
      final waiter = _Waiter(index);
      _waiting.add(waiter);
      // [_pump] counts the slot when it releases us, so we must not re-count.
      await waiter.gate.future;
    }

    var released = false;
    void release() {
      if (released) return;
      released = true;
      _active--;
      _pump();
    }

    final watchdog = Timer(slotWatchdog, release);
    try {
      return await body();
    } finally {
      watchdog.cancel();
      release();
    }
  }

  static void _pump() {
    while (_active < maxConcurrent && _waiting.isNotEmpty) {
      var best = 0;
      for (var i = 1; i < _waiting.length; i++) {
        if (_cost(_waiting[i].index) < _cost(_waiting[best].index)) best = i;
      }
      final waiter = _waiting.removeAt(best);
      _active++;
      waiter.gate.complete();
    }
  }

  /// Scheduling cost of a page: distance from the read position, biased
  /// forward. Mihon only ever preloads pages *after* the current one, so a page
  /// behind the reader yields to anything ahead of it — you are far more likely
  /// to keep going down than to scroll back up.
  static int _cost(int index) {
    final delta = index - _focus;
    return delta >= 0 ? delta : -delta * 8 + 4;
  }

  /// Test seam: the queue is process-wide static state.
  static void resetForTest() {
    _index.clear();
    _waiting.clear();
    _active = 0;
    _focus = 0;
    slotWatchdog = const Duration(seconds: 20);
  }

  static int get activeForTest => _active;

  static int get waitingForTest => _waiting.length;
}

class _Waiter {
  _Waiter(this.index);

  final int index;
  final Completer<void> gate = Completer<void>();
}
