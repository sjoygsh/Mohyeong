import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/track/track_updater.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../../domain/reader/model/reader_scale_type.dart';
import '../../domain/reader/model/reading_mode.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_chapter.dart';
import '../common/source_image.dart';

/// Reader screen — fetches the chapter's page list from the manga's source
/// and displays them in either a continuous webtoon scroll or a paged
/// view, depending on the effective [ReadingMode] (per-manga override
/// falling back to the user's global default).
///
/// Three failure modes are surfaced explicitly:
///   * Manga or chapter missing in DB → "Chapter not found".
///   * Source not installed → tell the user which source they need.
///   * Page fetch fails → show error + retry.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
  });

  final int mangaId;
  final int chapterId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late int _chapterId = widget.chapterId;
  Future<_ReaderData?>? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Honour the fullscreen pref by hiding the system bars while the reader
    // is open. Restored to the normal edge-to-edge mode on dispose so the
    // bars come back when we pop to the rest of the app.
    if (ref.read(readerFullscreenProvider)) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _applyKeepScreenOn();
    _applyBrightness();
    _applyOrientation();
    _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't hold the wakelock or a dimmed/brightened screen while the reader
    // is in the background; reacquire both when it comes back to the front.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // True backgrounding only. Deliberately NOT `inactive`, which also
        // fires on transient interruptions (notification shade, permission
        // dialogs, multi-window focus loss) and would flicker the screen
        // brightness mid-read.
        WakelockPlus.disable();
        ScreenBrightness().resetApplicationScreenBrightness();
      case AppLifecycleState.resumed:
        _applyKeepScreenOn();
        _applyBrightness();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Release the wakelock + restore system brightness so the reader's
    // settings don't leak into the rest of the app. Lift any orientation
    // lock so the rest of the app rotates freely again.
    WakelockPlus.disable();
    ScreenBrightness().resetApplicationScreenBrightness();
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// Pin the screen orientation per the reader's orientation pref. An
  /// empty list (Free) lets the device sensor decide.
  void _applyOrientation() {
    final orientation = ref.read(readerOrientationProvider);
    SystemChrome.setPreferredOrientations(orientation.orientations);
  }

  /// Acquire/release the wakelock per the keep-screen-on pref.
  void _applyKeepScreenOn() {
    if (ref.read(readerKeepScreenOnProvider)) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Apply the custom reader brightness (when enabled) to this activity's
  /// window. The 1..100 percent pref maps to the plugin's 0..1 range.
  void _applyBrightness() {
    if (!ref.read(readerCustomBrightnessProvider)) return;
    final pct = ref.read(readerBrightnessValueProvider).clamp(1, 100);
    ScreenBrightness().setApplicationScreenBrightness(pct / 100);
  }

  void _reload() {
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final extRepo = ref.read(extensionRepositoryProvider);
    final downloadRepo = ref.read(downloadRepositoryProvider);
    setState(() {
      _data = _loadReaderData(
        chapterRepo,
        mangaRepo,
        extRepo,
        downloadRepo,
        widget.mangaId,
        _chapterId,
      );
    });
  }

  void _jumpToChapter(int id) {
    _chapterId = id;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final globalMode = ref.watch(readerPreferencesProvider);
    final background = ref.watch(readerBackgroundProvider);
    final colorFilter = ref.watch(readerColorFilterProvider);
    return Scaffold(
      backgroundColor: background.color,
      body: FutureBuilder<_ReaderData?>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ReaderError(error: snap.error!);
          }
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: background.onColor),
            );
          }
          final data = snap.data;
          if (data == null) {
            return const _MissingChapter();
          }
          final effectiveMode =
              resolveReadingMode(data.manga.viewerFlags, globalMode);
          return _ReaderBody(
            data: data,
            mode: effectiveMode,
            background: background,
            colorFilter: colorFilter,
            onJumpToChapter: _jumpToChapter,
            onChangeMode: (mode) async {
              // Persist as a per-manga override. Preserve the upper bits
              // of `viewer` so future settings (rotation/scale/etc.) keep
              // their state.
              final preserved =
                  data.manga.viewerFlags & ~ReadingMode.mask;
              final newFlags = preserved | mode.flagValue;
              await ref
                  .read(mangaRepositoryProvider)
                  .setViewerFlags(data.manga.id, newFlags);
              _reload();
            },
            onPageChanged: (page) {
              // Fire-and-forget: avoid blocking the pager. Errors here are
              // not user-facing — they only impact sync resume.
              unawaited(
                ref
                    .read(chapterRepositoryProvider)
                    .setLastPageRead(data.chapter.id, page),
              );
            },
            onMarkRead: () async {
              final chapterRepo = ref.read(chapterRepositoryProvider);
              await chapterRepo.setRead(data.chapter.id, true);
              // Fire-and-forget tracker push. Failures are absorbed inside
              // TrackUpdater; the snackbar below confirms the local write.
              unawaited(
                ref.read(trackUpdaterProvider).setLastChapterRead(
                      mangaId: data.chapter.mangaId,
                      chapterNumber: data.chapter.chapterNumber,
                    ),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Marked as read.')),
              );
            },
          );
        },
      ),
    );
  }
}

Future<_ReaderData?> _loadReaderData(
  ChapterRepository chapterRepo,
  MangaRepository mangaRepo,
  ExtensionRepository extRepo,
  DownloadRepository downloadRepo,
  int mangaId,
  int chapterId,
) async {
  final manga = await mangaRepo.getById(mangaId);
  if (manga == null) return null;
  final siblings = await chapterRepo.getByMangaId(mangaId);
  Chapter? target;
  for (final c in siblings) {
    if (c.id == chapterId) {
      target = c;
      break;
    }
  }
  if (target == null) return null;

  final localPages =
      await downloadRepo.localPagePaths(manga.source, manga.id, chapterId);

  MangaSource? source;
  Object? sourceError;
  if (localPages == null) {
    try {
      source = await extRepo.getSource(manga.source.toString());
    } catch (e) {
      sourceError = e;
    }
  }

  return _ReaderData(
    chapter: target,
    manga: manga,
    siblings: siblings,
    source: source,
    sourceError: sourceError,
    localPagePaths: localPages,
  );
}

class _ReaderData {
  const _ReaderData({
    required this.chapter,
    required this.manga,
    required this.siblings,
    required this.source,
    required this.sourceError,
    required this.localPagePaths,
  });

  final Chapter chapter;
  final Manga manga;
  final List<Chapter> siblings;
  final MangaSource? source;
  final Object? sourceError;
  final List<String>? localPagePaths;

  Chapter? get previousChapter {
    final idx = siblings.indexWhere((c) => c.id == chapter.id);
    if (idx <= 0) return null;
    return siblings[idx - 1];
  }

  Chapter? get nextChapter {
    final idx = siblings.indexWhere((c) => c.id == chapter.id);
    if (idx < 0 || idx >= siblings.length - 1) return null;
    return siblings[idx + 1];
  }
}

/// The visible reader surface around the page viewport. Holds the
/// "chrome visible" toggle (tap anywhere on the viewport to hide/show
/// the header and bottom strip) plus the current/total page state that
/// powers the page indicator and the paged-mode slider.
class _ReaderBody extends ConsumerStatefulWidget {
  const _ReaderBody({
    required this.data,
    required this.mode,
    required this.background,
    required this.colorFilter,
    required this.onJumpToChapter,
    required this.onChangeMode,
    required this.onPageChanged,
    required this.onMarkRead,
  });

  final _ReaderData data;
  final ReadingMode mode;
  final ReaderBackground background;
  final ReaderColorFilter colorFilter;
  final ValueChanged<int> onJumpToChapter;
  final ValueChanged<ReadingMode> onChangeMode;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onMarkRead;

  @override
  ConsumerState<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends ConsumerState<_ReaderBody> {
  bool _chromeVisible = true;
  int _currentPage = 0;
  int _totalPages = 0;
  // Used by the paged-mode slider to drive the underlying PageController.
  // Bumped whenever the user moves the slider; the viewport reads it via
  // [_ViewportRequest] and animates to the new index.
  int _seekRequestId = 0;
  int _seekTarget = 0;
  // Auto-hide timer for the chrome overlay. Re-armed each time the
  // chrome becomes visible (initial state + every toggle-to-visible).
  // `null` means either auto-hide is disabled (delay = 0) or the
  // chrome is currently hidden.
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    // Chrome starts visible — arm the initial countdown so the reader
    // settles into a clean view if the user doesn't tap anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _armAutoHide();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _armAutoHide() {
    _autoHideTimer?.cancel();
    final seconds = ref.read(readerAutoHideChromeSecondsProvider);
    if (seconds <= 0 || !_chromeVisible) return;
    _autoHideTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      if (_chromeVisible) setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _armAutoHide();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  void _onPageChanged(int page) {
    if (page != _currentPage) {
      setState(() => _currentPage = page);
    }
    widget.onPageChanged(page);
  }

  void _onTotalChanged(int total) {
    if (total != _totalPages) {
      // Defer to next frame; this callback fires during the viewport's
      // build, so calling setState synchronously would mark dirty during
      // build and trip the framework.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _totalPages = total);
      });
    }
  }

  void _seekTo(int page) {
    setState(() {
      _currentPage = page;
      _seekTarget = page;
      _seekRequestId++;
    });
  }

  /// Handle a tap on the page viewport. With tap-to-navigate on (paged
  /// modes only), tapping the left/right third turns a page — falling
  /// through to the adjacent chapter at the chapter boundary. The centre
  /// third (and any tap in continuous mode) just toggles the chrome.
  void _handleViewportTap(TapUpDetails details, double width) {
    final tapNav = ref.read(readerTapToNavigateProvider);
    if (!widget.mode.isPaged || !tapNav || width <= 0) {
      _toggleChrome();
      return;
    }
    final x = details.localPosition.dx;
    final leftZone = x < width / 3;
    final rightZone = x > width * 2 / 3;
    if (!leftZone && !rightZone) {
      _toggleChrome();
      return;
    }
    // Right zone advances by default; RTL reading and the user invert
    // pref each flip that mapping.
    var forward = rightZone;
    if (widget.mode == ReadingMode.rightToLeft) forward = !forward;
    if (ref.read(readerTapNavigateInvertProvider)) forward = !forward;
    _navigatePage(forward: forward);
  }

  /// Turn one page in [forward] direction, or jump to the adjacent
  /// chapter when stepping past either end of the current chapter.
  void _navigatePage({required bool forward}) {
    final target = forward ? _currentPage + 1 : _currentPage - 1;
    if (target >= 0 && target < _totalPages) {
      _seekTo(target);
      return;
    }
    final skipRead = ref.read(readerSkipReadProvider);
    final skipDupe = ref.read(readerSkipDupeProvider);
    final skipFiltered = ref.read(readerSkipFilteredProvider);
    final adjacent = _adjacentChapter(widget.data,
        forward: forward,
        skipRead: skipRead,
        skipDupe: skipDupe,
        skipFiltered: skipFiltered);
    if (adjacent != null) widget.onJumpToChapter(adjacent.id);
  }

  /// Resolve the chapter the prev/next buttons should jump to, honouring
  /// the skip-read and skip-dupe navigation prefs. Walks [data.siblings]
  /// (reading order) from the current chapter in [forward] direction,
  /// skipping chapters already marked read (when [skipRead]) and chapters
  /// that repeat the current chapter's number — different scanlations of
  /// the same chapter (when [skipDupe]). Falls back to the immediate
  /// neighbour if every candidate is skipped, so the buttons never go
  /// dead while real chapters remain.
  Chapter? _adjacentChapter(
    _ReaderData data, {
    required bool forward,
    required bool skipRead,
    required bool skipDupe,
    required bool skipFiltered,
  }) {
    final immediate = forward ? data.nextChapter : data.previousChapter;
    if (immediate == null || (!skipRead && !skipDupe && !skipFiltered)) {
      return immediate;
    }
    final siblings = data.siblings;
    final currentIdx = siblings.indexWhere((c) => c.id == data.chapter.id);
    if (currentIdx < 0) return immediate;
    final step = forward ? 1 : -1;
    for (var i = currentIdx + step; i >= 0 && i < siblings.length; i += step) {
      final candidate = siblings[i];
      if (skipRead && candidate.read) continue;
      if (skipDupe &&
          candidate.chapterNumber == data.chapter.chapterNumber) {
        continue;
      }
      if (skipFiltered && !_passesChapterFilter(data.manga, candidate)) {
        continue;
      }
      return candidate;
    }
    return immediate;
  }

  /// Whether [chapter] survives the manga's chapter-filter flags. Honours
  /// the unread and bookmarked tri-state axes (matching the manga-details
  /// filter sheet). The downloaded axis is intentionally ignored here — it
  /// needs an async filesystem probe that doesn't belong in synchronous
  /// page-turn navigation.
  bool _passesChapterFilter(Manga manga, Chapter chapter) {
    switch (manga.unreadFilter) {
      case TriState.enabledIs:
        if (chapter.read) return false;
      case TriState.enabledNot:
        if (!chapter.read) return false;
      case TriState.disabled:
        break;
    }
    switch (manga.bookmarkedFilter) {
      case TriState.enabledIs:
        if (!chapter.bookmark) return false;
      case TriState.enabledNot:
        if (chapter.bookmark) return false;
      case TriState.disabled:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final skipRead = ref.watch(readerSkipReadProvider);
    final skipDupe = ref.watch(readerSkipDupeProvider);
    final skipFiltered = ref.watch(readerSkipFilteredProvider);
    final prev = _adjacentChapter(data, forward: false,
        skipRead: skipRead, skipDupe: skipDupe, skipFiltered: skipFiltered);
    final next = _adjacentChapter(data, forward: true,
        skipRead: skipRead, skipDupe: skipDupe, skipFiltered: skipFiltered);
    final showSlider = widget.mode.isPaged && _totalPages > 1;
    final showPageNumber = ref.watch(readerShowPageNumberProvider);
    final grayscale = ref.watch(readerGrayscaleProvider);
    final invert = ref.watch(readerInvertedColorsProvider);
    final fit = ReaderScaleType.fromKey(ref.watch(readerScaleTypeProvider))
        .boxFit;
    final sidePaddingPct =
        ref.watch(readerWebtoonSidePaddingProvider).clamp(0, 25);

    Widget viewport = _ReaderViewport(
      data: data,
      mode: widget.mode,
      fit: fit,
      sidePaddingFraction: sidePaddingPct / 100,
      onPageChanged: _onPageChanged,
      onTotalChanged: _onTotalChanged,
      seekRequest: _ViewportSeekRequest(
        requestId: _seekRequestId,
        target: _seekTarget,
      ),
    );
    // Page-art colour adjustments. Applied to the page viewport only (not
    // the chrome) by wrapping before the gesture/Stack layers. Greyscale
    // and invert compose by nesting the two ColorFiltered layers.
    if (grayscale) {
      viewport = ColorFiltered(
        colorFilter: _grayscaleFilter,
        child: viewport,
      );
    }
    if (invert) {
      viewport = ColorFiltered(
        colorFilter: _invertFilter,
        child: viewport,
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          // Tap on the viewport toggles chrome. translucent so taps on
          // the underlying images still register where the viewport
          // already handles them (zoom on paged mode etc.).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (d) =>
                  _handleViewportTap(d, MediaQuery.sizeOf(context).width),
              child: viewport,
            ),
          ),
          // Reader colour filter (sepia/yellow/blue tint). Sits above
          // the pages but below the chrome so the filter affects only
          // the page art, not the controls. IgnorePointer so taps still
          // pass through to the toggle-chrome gesture detector.
          if (widget.colorFilter.overlay != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: widget.colorFilter.overlay!),
              ),
            ),
          // Top chrome.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: _chromeVisible ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _chromeVisible ? 1 : 0,
                child: Container(
                  color: const Color(0xCC000000),
                  child: _ReaderHeader(
                    manga: data.manga,
                    chapter: data.chapter,
                    mode: widget.mode,
                    onChangeMode: widget.onChangeMode,
                  ),
                ),
              ),
            ),
          ),
          // Bottom chrome: page indicator + optional slider + nav row.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: _chromeVisible ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _chromeVisible ? 1 : 0,
                child: Container(
                  color: const Color(0xCC000000),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showSlider)
                        _PageSlider(
                          current: _currentPage,
                          total: _totalPages,
                          reversed: widget.mode == ReadingMode.rightToLeft,
                          onChanged: _seekTo,
                        ),
                      if (showPageNumber)
                        _PageIndicator(
                          current: _currentPage,
                          total: _totalPages,
                        ),
                      _ReaderControls(
                        onPrev: prev == null
                            ? null
                            : () => widget.onJumpToChapter(prev.id),
                        onNext: next == null
                            ? null
                            : () => widget.onJumpToChapter(next.id),
                        onMarkRead: widget.onMarkRead,
                        alreadyRead: data.chapter.read,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Luminance-weighted desaturation (Rec. 709 coefficients).
const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Colour negative — flip each channel around its midpoint.
const ColorFilter _invertFilter = ColorFilter.matrix(<double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
]);

class _ViewportSeekRequest {
  const _ViewportSeekRequest({required this.requestId, required this.target});

  /// Monotonic id that ticks every time the user drags the slider — the
  /// viewport listens for this to know whether the request is fresh, since
  /// we may emit two requests with the same `target` index back-to-back.
  final int requestId;
  final int target;
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '${current + 1} / $total',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _PageSlider extends StatelessWidget {
  const _PageSlider({
    required this.current,
    required this.total,
    required this.reversed,
    required this.onChanged,
  });

  final int current;
  final int total;
  final bool reversed;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    // For RTL we still want the leftmost slider position to mean "earliest"
    // page from the reader's POV. Slider's value space stays 0..total-1; we
    // just flip the mapping. Mihon does the same.
    final value = reversed
        ? (total - 1 - current).clamp(0, total - 1).toDouble()
        : current.clamp(0, total - 1).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Slider(
        min: 0,
        max: (total - 1).toDouble(),
        divisions: total - 1,
        value: value,
        label: '${current + 1}',
        onChanged: (v) {
          final raw = v.round();
          final target =
              reversed ? (total - 1 - raw).clamp(0, total - 1) : raw;
          onChanged(target);
        },
      ),
    );
  }
}

/// Dispatches between the three rendering paths (local files, source pages,
/// or source-unavailable error) and threads the chosen [ReadingMode]
/// through to the actual page list widget.
class _ReaderViewport extends StatelessWidget {
  const _ReaderViewport({
    required this.data,
    required this.mode,
    required this.fit,
    required this.sidePaddingFraction,
    required this.onPageChanged,
    required this.onTotalChanged,
    required this.seekRequest,
  });

  final _ReaderData data;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalChanged;
  final _ViewportSeekRequest seekRequest;

  @override
  Widget build(BuildContext context) {
    if (data.localPagePaths != null) {
      // Report total synchronously — local pages are already enumerated.
      onTotalChanged(data.localPagePaths!.length);
      return _LocalPageList(
        paths: data.localPagePaths!,
        mode: mode,
        fit: fit,
        sidePaddingFraction: sidePaddingFraction,
        initialPage: data.chapter.lastPageRead,
        onPageChanged: onPageChanged,
        seekRequest: seekRequest,
      );
    }
    if (data.source == null) {
      onTotalChanged(0);
      return _SourceUnavailable(
        mangaSourceId: data.manga.source,
        error: data.sourceError,
      );
    }
    return _PageList(
      source: data.source!,
      chapter: data.chapter,
      mode: mode,
      fit: fit,
      sidePaddingFraction: sidePaddingFraction,
      onPageChanged: onPageChanged,
      onTotalChanged: onTotalChanged,
      seekRequest: seekRequest,
    );
  }
}

class _PageList extends StatefulWidget {
  const _PageList({
    required this.source,
    required this.chapter,
    required this.mode,
    required this.fit,
    required this.sidePaddingFraction,
    required this.onPageChanged,
    required this.onTotalChanged,
    required this.seekRequest,
  });

  final MangaSource source;
  final Chapter chapter;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalChanged;
  final _ViewportSeekRequest seekRequest;

  @override
  State<_PageList> createState() => _PageListState();
}

class _PageListState extends State<_PageList> {
  Future<List<SourcePage>>? _pages;

  @override
  void initState() {
    super.initState();
    _refetch();
  }

  void _refetch() {
    _pages = widget.source.fetchPageList(
      SourceChapter(url: widget.chapter.url, name: widget.chapter.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SourcePage>>(
      future: _pages,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load pages: ${snap.error}',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(_refetch);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final pages = snap.data!;
        // Report total once we know it. Routing through a post-frame
        // callback because we're inside `build()`.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onTotalChanged(pages.length);
        });
        if (pages.isEmpty) {
          return const Center(
            child: Text('No pages.', style: TextStyle(color: Colors.white70)),
          );
        }
        return _PagesView(
          count: pages.length,
          mode: widget.mode,
          sidePaddingFraction: widget.sidePaddingFraction,
          initialPage: widget.chapter.lastPageRead,
          onPageChanged: widget.onPageChanged,
          seekRequest: widget.seekRequest,
          itemBuilder: (_, i) {
            final page = pages[i];
            final imageUrl = page.imageUrl ?? page.url;
            return SourceImage(
              url: imageUrl,
              fit: widget.fit,
              headers: page.headers,
              placeholder: (_) => const SizedBox(
                height: 400,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (_, error) => SizedBox(
                height: 400,
                child: Center(
                  child: Text(
                    'Page ${i + 1} failed: $error',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LocalPageList extends StatelessWidget {
  const _LocalPageList({
    required this.paths,
    required this.mode,
    required this.fit,
    required this.sidePaddingFraction,
    required this.initialPage,
    required this.onPageChanged,
    required this.seekRequest,
  });

  final List<String> paths;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final _ViewportSeekRequest seekRequest;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const Center(
        child: Text('No pages.', style: TextStyle(color: Colors.white70)),
      );
    }
    return _PagesView(
      count: paths.length,
      mode: mode,
      sidePaddingFraction: sidePaddingFraction,
      initialPage: initialPage,
      onPageChanged: onPageChanged,
      seekRequest: seekRequest,
      itemBuilder: (_, i) => Image.file(
        File(paths[i]),
        fit: fit,
        errorBuilder: (_, error, _) => SizedBox(
          height: 400,
          child: Center(
            child: Text(
              'Page ${i + 1} failed: $error',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mode-agnostic page list. Continuous modes use a [ListView]; paged modes
/// use a [PageView] with the axis + reverse flag set from the [ReadingMode].
/// Both paths report the current page index via [onPageChanged] (1-based
/// pages are presented to users elsewhere, but storage uses 0-based to
/// match Mihon's `last_page_read`).
class _PagesView extends StatefulWidget {
  const _PagesView({
    required this.count,
    required this.mode,
    required this.sidePaddingFraction,
    required this.initialPage,
    required this.onPageChanged,
    required this.seekRequest,
    required this.itemBuilder,
  });

  final int count;
  final ReadingMode mode;
  final double sidePaddingFraction;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final _ViewportSeekRequest seekRequest;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_PagesView> createState() => _PagesViewState();
}

class _PagesViewState extends State<_PagesView> {
  PageController? _pageController;
  ScrollController? _scrollController;
  int _lastReported = -1;

  @override
  void initState() {
    super.initState();
    final clamped =
        widget.initialPage.clamp(0, (widget.count - 1).clamp(0, widget.count));
    if (widget.mode.isPaged) {
      _pageController = PageController(initialPage: clamped);
    } else {
      _scrollController = ScrollController();
      // Defer jump until after layout so the viewport has a size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _scrollController == null) return;
        // We don't know each page's height in advance; the best we can do
        // for webtoon resume is jump proportionally. Users still get the
        // chapter open at roughly the right spot.
        final pos = _scrollController!.position;
        final ratio = widget.count == 0 ? 0 : clamped / widget.count;
        _scrollController!.jumpTo(pos.maxScrollExtent * ratio);
      });
    }
    _lastReported = clamped;
  }

  @override
  void didUpdateWidget(covariant _PagesView old) {
    super.didUpdateWidget(old);
    // Slider drove a seek: jump the underlying PageController. Continuous
    // mode has no random-access seek surface — slider only shows in paged
    // mode anyway so this branch is a no-op there.
    if (widget.seekRequest.requestId != old.seekRequest.requestId &&
        _pageController != null) {
      final target =
          widget.seekRequest.target.clamp(0, (widget.count - 1).clamp(0, widget.count));
      _pageController!.jumpToPage(target);
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  void _report(int page) {
    if (page == _lastReported) return;
    _lastReported = page;
    widget.onPageChanged(page);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mode.isPaged) {
      // Continuous (webtoon / continuous vertical). Both render the same
      // way in v1.0 — vertical scrolling list of fit-width images.
      return NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (notif is ScrollEndNotification &&
              _scrollController != null &&
              widget.count > 0) {
            final pos = _scrollController!.position;
            final max = pos.maxScrollExtent;
            if (max > 0) {
              final ratio = pos.pixels / max;
              final approx =
                  (ratio * widget.count).floor().clamp(0, widget.count - 1);
              _report(approx);
            }
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.count,
          // Webtoon side padding: inset each page horizontally by a
          // fraction of the viewport width so strips don't run edge-to-
          // edge on wide screens. 0 = no inset (the default).
          padding: widget.sidePaddingFraction <= 0
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width *
                      widget.sidePaddingFraction,
                ),
          itemBuilder: widget.itemBuilder,
        ),
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection:
          widget.mode.isHorizontal ? Axis.horizontal : Axis.vertical,
      reverse: widget.mode == ReadingMode.rightToLeft,
      itemCount: widget.count,
      onPageChanged: _report,
      itemBuilder: (ctx, i) => _ZoomablePage(
        child: Center(child: widget.itemBuilder(ctx, i)),
      ),
    );
  }
}

/// A single paged image wrapped in an [InteractiveViewer] with double-tap
/// to zoom. The zoom-in/out transition duration comes from
/// [readerDoubleTapAnimSpeedProvider]; a value of 0 applies the transform
/// instantly. Double-tapping while zoomed resets back to fit.
class _ZoomablePage extends ConsumerStatefulWidget {
  const _ZoomablePage({required this.child});

  final Widget child;

  @override
  ConsumerState<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends ConsumerState<_ZoomablePage>
    with SingleTickerProviderStateMixin {
  static const _zoomScale = 2.5;

  final TransformationController _controller = TransformationController();
  late final AnimationController _animController =
      AnimationController(vsync: this);
  Animation<Matrix4>? _animation;

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _applyMatrix(Matrix4 target) {
    final speedMs = ref.read(readerDoubleTapAnimSpeedProvider);
    if (speedMs <= 0) {
      _controller.value = target;
      return;
    }
    _animController.duration = Duration(milliseconds: speedMs);
    _animation?.removeListener(_onAnimTick);
    _animation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    )..addListener(_onAnimTick);
    _animController
      ..reset()
      ..forward();
  }

  void _onAnimTick() {
    final anim = _animation;
    if (anim != null) _controller.value = anim.value;
  }

  void _handleDoubleTap(TapDownDetails details) {
    // Already zoomed in → reset to fit.
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _applyMatrix(Matrix4.identity());
      return;
    }
    // Zoom in centred on the tapped point.
    final position = details.localPosition;
    final target = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (_zoomScale - 1),
        -position.dy * (_zoomScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_zoomScale, _zoomScale, _zoomScale, 1);
    _applyMatrix(target);
  }

  @override
  Widget build(BuildContext context) {
    TapDownDetails? lastTapDown;
    return GestureDetector(
      onDoubleTapDown: (d) => lastTapDown = d,
      onDoubleTap: () {
        if (lastTapDown != null) _handleDoubleTap(lastTapDown!);
      },
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 4,
        child: widget.child,
      ),
    );
  }
}

class _SourceUnavailable extends StatelessWidget {
  const _SourceUnavailable({required this.mangaSourceId, required this.error});

  final int mangaSourceId;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 12),
            Text(
              'Source not installed.',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'This manga was added from source id $mangaSourceId. Install '
              'the matching extension on the Browse tab to read it.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                'Detail: $error',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({
    required this.manga,
    required this.chapter,
    required this.mode,
    required this.onChangeMode,
  });

  final Manga manga;
  final Chapter chapter;
  final ReadingMode mode;
  final ValueChanged<ReadingMode> onChangeMode;

  Future<void> _pickMode(BuildContext context) async {
    final picked = await showDialog<ReadingMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Reading mode'),
        children: [
          RadioGroup<ReadingMode>(
            groupValue: mode,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in ReadingMode.values)
                  if (m != ReadingMode.defaultMode)
                    RadioListTile<ReadingMode>(
                      title: Text(m.label),
                      value: m,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && picked != mode) {
      onChangeMode(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manga.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  chapter.name.isEmpty
                      ? 'Chapter ${chapter.chapterNumber}'
                      : chapter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'Reading mode (${mode.label})',
            onPressed: () => _pickMode(context),
          ),
        ],
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.onPrev,
    required this.onNext,
    required this.onMarkRead,
    required this.alreadyRead,
  });

  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onMarkRead;
  final bool alreadyRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            tooltip: 'Previous chapter',
            onPressed: onPrev,
          ),
          TextButton(
            onPressed: alreadyRead ? null : onMarkRead,
            child: Text(alreadyRead ? 'Read' : 'Mark as read'),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            tooltip: 'Next chapter',
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to open chapter: $error',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _MissingChapter extends StatelessWidget {
  const _MissingChapter();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: const Center(
        child: Text(
          'Chapter not found.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
