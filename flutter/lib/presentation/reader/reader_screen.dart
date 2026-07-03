import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/base/base_preferences.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/cover/cover_cache.dart';
import '../../data/download/download_preferences.dart';
import '../../data/download/download_repository.dart';
import '../../data/history/history_repository.dart';
import '../../data/library/library_update_preference.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_image_actions.dart';
import '../../data/reader/reader_preferences.dart';
import '../../data/reader/reader_volume_keys.dart';
import '../../data/security/secure_screen.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/incognito_preferences.dart';
import '../../data/track/track_preferences.dart';
import '../../data/track/track_updater.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/chapter/service/set_read_status.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../../domain/reader/model/reading_mode.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_chapter.dart';
import '../common/crop_borders_image.dart';
import '../common/source_image.dart';
import '../common/webview_screen.dart';
import 'reader_settings_sheet.dart';

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

  /// The chapter currently being timed for the reading-history record, and
  /// when its active foreground session last started. Mihon records a
  /// history entry the moment a chapter is opened (so it surfaces in the
  /// History tab even if you only view the first page) and accumulates the
  /// time spent reading on top via the `upsertHistory` ON CONFLICT clause.
  int? _historyChapterId;
  DateTime? _sessionStartedAt;

  // Debounced reading-progress persistence. Writing `last_page_read` on
  // EVERY swipe invalidated drift query streams per page turn, which
  // rebuilt the details screen sitting under the reader plus the
  // library/updates/history tabs kept alive in the home IndexedStack —
  // a rebuild storm that made paging visibly stutter. Progress is still
  // persisted, just coalesced; flushed on chapter change and dispose.
  Timer? _progressTimer;
  int? _pendingProgressChapterId;
  int _pendingProgressPage = 0;

  void _queueProgress(int chapterId, int page) {
    _pendingProgressChapterId = chapterId;
    _pendingProgressPage = page;
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 600), _flushProgress);
  }

  void _flushProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    final chapterId = _pendingProgressChapterId;
    if (chapterId == null) return;
    _pendingProgressChapterId = null;
    unawaited(
      ref
          .read(chapterRepositoryProvider)
          .setLastPageRead(chapterId, _pendingProgressPage),
    );
  }

  /// Resolved once per session from the manga's source (see [_loadReaderData]).
  /// While true the reader persists nothing — no history, no progress, no
  /// tracker pushes — mirroring Mihon's `ReaderViewModel.incognitoMode`.
  bool _incognito = false;

  /// The orientation lock currently pushed to the platform, so the
  /// effective (per-manga override or global) orientation is re-applied
  /// only when it actually changes.
  ReaderOrientation? _appliedOrientation;

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
    _applyCutout();
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
        // Bank read time and stop the clock so backgrounded time doesn't
        // inflate the chapter's read duration.
        _flushReadTime();
        _sessionStartedAt = null;
      case AppLifecycleState.resumed:
        _applyKeepScreenOn();
        _applyBrightness();
        // Restart the read-time clock for the chapter still on screen.
        if (_historyChapterId != null) _sessionStartedAt = DateTime.now();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    // Bank the final read-time slice for the chapter on screen before tearing
    // the reader down, and persist any coalesced page progress.
    _flushProgress();
    _flushReadTime();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Give the notch letterbox back to the rest of the app.
    SecureScreen.setCutoutShortEdges(false);
    // Release the wakelock + restore system brightness so the reader's
    // settings don't leak into the rest of the app. Lift any orientation
    // lock so the rest of the app rotates freely again.
    WakelockPlus.disable();
    ScreenBrightness().resetApplicationScreenBrightness();
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  /// Pin the screen orientation per the reader's orientation pref. An
  /// empty list (Free) lets the device sensor decide. Called with the
  /// global default before the manga resolves; once it does, the
  /// effective (per-manga override or global) value is applied from
  /// `build` whenever it changes.
  /// Mihon draws under the notch only while the reader is fullscreen and
  /// `cutout_short` is on (drawUnderCutout); everywhere else the window
  /// letterboxes the cutout.
  void _applyCutout() {
    SecureScreen.setCutoutShortEdges(
      ref.read(readerFullscreenProvider) &&
          ref.read(readerCutoutShortProvider),
    );
  }

  void _applyOrientation() {
    _setOrientation(ref.read(readerOrientationProvider));
  }

  void _setOrientation(ReaderOrientation orientation) {
    if (orientation == _appliedOrientation) return;
    _appliedOrientation = orientation;
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
    // Persist pending progress before the loaded chapter switches out from
    // under the debounce.
    _flushProgress();
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final extRepo = ref.read(extensionRepositoryProvider);
    final downloadRepo = ref.read(downloadRepositoryProvider);
    final future = _loadReaderData(
      chapterRepo,
      mangaRepo,
      extRepo,
      downloadRepo,
      widget.mangaId,
      _chapterId,
      globalIncognito: ref.read(incognitoModeProvider),
      incognitoExtensions: ref.read(incognitoExtensionsProvider),
      downloadedOnly: ref.read(downloadedOnlyProvider),
    );
    // Stamp a history entry as soon as the chapter resolves, mirroring
    // Mihon's "open == read" behaviour — unless the source is incognito, in
    // which case nothing is recorded for the whole session.
    future.then((data) {
      if (data != null && mounted) {
        _incognito = data.incognito;
        if (!_incognito) _startHistorySession(data.chapter.id);
      }
    });
    setState(() {
      _data = future;
    });
  }

  void _jumpToChapter(int id) {
    // Bank the time spent on the chapter we're leaving before switching.
    _flushReadTime();
    _chapterId = id;
    _reload();
  }

  /// Begin (or resume) timing a chapter for the reading-history record and
  /// immediately upsert a `last_read = now` row so the chapter shows up in
  /// the History tab right away.
  void _startHistorySession(int chapterId) {
    _historyChapterId = chapterId;
    _sessionStartedAt = DateTime.now();
    unawaited(
      ref.read(historyRepositoryProvider).upsert(
            chapterId: chapterId,
            readAt: DateTime.now(),
            timeReadMs: 0,
          ),
    );
  }

  /// Add the elapsed foreground time since the last checkpoint onto the
  /// current chapter's history row and refresh its `last_read` to now. Resets
  /// the session clock so the same span isn't counted twice. No-op when no
  /// chapter is being timed.
  void _flushReadTime() {
    final chapterId = _historyChapterId;
    final startedAt = _sessionStartedAt;
    if (chapterId == null || startedAt == null) return;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _sessionStartedAt = DateTime.now();
    if (elapsedMs <= 0) return;
    unawaited(
      ref.read(historyRepositoryProvider).upsert(
            chapterId: chapterId,
            readAt: DateTime.now(),
            timeReadMs: elapsedMs,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final globalMode = ref.watch(readerPreferencesProvider);
    final background = ref.watch(readerBackgroundProvider);
    final brightness = Theme.of(context).brightness;
    // Apply display prefs live while the reader is open, so toggling them
    // from the in-reader settings sheet takes effect immediately (Kotlin
    // observes these flows in ReaderActivity).
    ref.listen(readerFullscreenProvider, (_, next) {
      SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      _applyCutout();
    });
    ref.listen(readerCutoutShortProvider, (_, _) => _applyCutout());
    ref.listen(readerKeepScreenOnProvider, (_, _) => _applyKeepScreenOn());
    ref.listen(readerCustomBrightnessProvider, (_, next) {
      if (next) {
        _applyBrightness();
      } else {
        ScreenBrightness().resetApplicationScreenBrightness();
      }
    });
    ref.listen(readerBrightnessValueProvider, (_, _) => _applyBrightness());
    return Scaffold(
      backgroundColor: background.resolveColor(brightness),
      body: FutureBuilder<_ReaderData?>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ReaderError(error: snap.error!);
          }
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(
                color: background.resolveOnColor(brightness),
              ),
            );
          }
          final data = snap.data;
          if (data == null) {
            return const _MissingChapter();
          }
          final effectiveMode =
              resolveReadingMode(data.manga.viewerFlags, globalMode);
          // Per-manga orientation override (bits 3..5 of `viewer`),
          // falling back to the global default — applied to the platform
          // whenever the effective value changes (incl. pref changes from
          // the in-reader sheet, which rebuild via the watch).
          final effectiveOrientation = resolveReaderOrientation(
            data.manga.viewerFlags,
            ref.watch(readerOrientationProvider),
          );
          _setOrientation(effectiveOrientation);
          return _ReaderBody(
            data: data,
            mode: effectiveMode,
            orientation: effectiveOrientation,
            background: background,
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
            onChangeOrientation: (orientation) async {
              // Per-manga orientation override in bits 3..5 of `viewer`;
              // null clears back to "use global default" (bits = 0).
              final preserved =
                  data.manga.viewerFlags & ~ReaderOrientation.mask;
              final newFlags = preserved | (orientation?.flagValue ?? 0);
              await ref
                  .read(mangaRepositoryProvider)
                  .setViewerFlags(data.manga.id, newFlags);
              _reload();
            },
            onPageChanged: (page) {
              // Skip persisting progress in incognito (Mihon
              // `updateChapterProgress` is gated on `!incognitoMode`).
              if (_incognito) return;
              _queueProgress(data.chapter.id, page);
            },
            onReachedEnd: () {
              // Auto-mark on reaching the last page. Silent (no snackbar) and
              // fire-and-forget — mirrors Mihon marking the chapter read once
              // the final page is shown, plus the tracker last-read push.
              // Suppressed entirely in incognito (Mihon
              // `updateChapterProgressOnComplete` only runs from the
              // `!incognitoMode` branch of `updateChapterProgress`).
              if (_incognito) return;
              unawaited(
                ref
                    .read(chapterRepositoryProvider)
                    .setRead(data.chapter.id, true),
              );
              // "Mark duplicate read chapter as read → After reading a
              // chapter" (Kotlin MARK_DUPLICATE_CHAPTER_READ_EXISTING):
              // unread siblings sharing this chapter number get marked read
              // too, without a tracker push.
              if (ref
                  .read(markDuplicateReadChapterAsReadProvider)
                  .contains(MarkDuplicateRead.readExisting)) {
                final repo = ref.read(chapterRepositoryProvider);
                for (final sibling in data.siblings) {
                  if (sibling.id != data.chapter.id &&
                      !sibling.read &&
                      sibling.chapterNumber >= 0 &&
                      sibling.chapterNumber == data.chapter.chapterNumber) {
                    unawaited(repo.setRead(sibling.id, true));
                  }
                }
              }
              // Mirrors Mihon `updateChapterProgressOnComplete` →
              // `updateTrackChapterRead`, gated by "Update progress after
              // reading" (`autoUpdateTrack`).
              if (ref.read(autoUpdateTrackProvider)) {
                unawaited(
                  ref.read(trackUpdaterProvider).setLastChapterRead(
                        mangaId: data.chapter.mangaId,
                        chapterNumber: data.chapter.chapterNumber,
                        volumeNumber: data.chapter.volumeNumber,
                      ),
                );
              }
              // Drop the download `removeAfterReadSlots` chapters back, in
              // reading order (Mihon `deleteChapterIfNeeded`). Independent of
              // `remove_after_marked_as_read`.
              unawaited(
                ref.read(setReadStatusProvider).deleteReadChapterSlot(
                      manga: data.manga,
                      orderedChapters: data.siblings,
                      current: data.chapter,
                    ),
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
  int chapterId, {
  required bool globalIncognito,
  required Set<String> incognitoExtensions,
  required bool downloadedOnly,
}) async {
  final manga = await mangaRepo.getById(mangaId);
  if (manga == null) return null;
  var siblings = await chapterRepo.getByMangaId(mangaId);
  // "Downloaded only" mode: the reader's chapter list (prev/next navigation)
  // keeps only downloaded chapters, mirroring Kotlin's
  // `chaptersForReader.filterDownloaded(manga)`. Local manga are exempt and
  // the open chapter itself always stays in the list.
  if (downloadedOnly && manga.source != 0) {
    final downloadedIds =
        await downloadRepo.listDownloadedChapterIds(manga.source, manga.id);
    siblings = siblings
        .where((c) => c.id == chapterId || downloadedIds.contains(c.id))
        .toList(growable: false);
  }
  // getByMangaId returns newest-first (sourceOrder 0 == newest). The reader
  // navigates in READING order — Kotlin sorts with getChapterSort(manga,
  // sortDescending = false) before indexing — so flip to oldest-first.
  // Without this, prev/next chapter (and the boundary fall-through from
  // page turns / volume keys) walk backwards.
  siblings = siblings.reversed.toList(growable: false);
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

  // Resolve the source even when the chapter is downloaded — the viewport
  // won't need it for pages, but the top bar's WebView / browser / share
  // overflow still wants the chapter URL (Kotlin gates those purely on the
  // source being an HttpSource). Failure is only fatal when the pages must
  // actually be fetched from the source.
  MangaSource? source;
  Object? sourceError;
  try {
    source = await extRepo.getSource(manga.source.toString());
  } catch (e) {
    if (localPages == null) sourceError = e;
  }

  // Resolve incognito once for the whole session (1:1 with Mihon's
  // `by lazy { getIncognitoState.await(manga?.source) }`).
  final incognito = await resolveIncognitoState(
    globalIncognito: globalIncognito,
    incognitoExtensions: incognitoExtensions,
    extensionRepository: extRepo,
    sourceId: manga.source,
  );

  return _ReaderData(
    chapter: target,
    manga: manga,
    siblings: siblings,
    source: source,
    sourceError: sourceError,
    localPagePaths: localPages,
    incognito: incognito,
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
    required this.incognito,
  });

  final Chapter chapter;
  final Manga manga;
  final List<Chapter> siblings;
  final MangaSource? source;
  final Object? sourceError;
  final List<String>? localPagePaths;
  final bool incognito;

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

/// Lightweight handle to a single page's image, threaded up from the page
/// list once the pages resolve so the long-press "Set as cover" action can
/// rebuild the page's [ImageProvider] (via [SourceImage.providerFor]) and
/// capture its bytes. Carries everything the backend detection needs: the
/// URL/path plus any per-source HTTP [headers].
class _PageRef {
  const _PageRef(this.url, this.headers);

  final String url;
  final Map<String, String>? headers;
}

/// The visible reader surface around the page viewport. Holds the
/// "chrome visible" toggle (tap anywhere on the viewport to hide/show
/// the header and bottom strip) plus the current/total page state that
/// powers the page indicator and the paged-mode slider.
class _ReaderBody extends ConsumerStatefulWidget {
  const _ReaderBody({
    required this.data,
    required this.mode,
    required this.orientation,
    required this.background,
    required this.onJumpToChapter,
    required this.onChangeMode,
    required this.onChangeOrientation,
    required this.onPageChanged,
    required this.onReachedEnd,
  });

  final _ReaderData data;
  final ReadingMode mode;

  /// Effective orientation (per-manga override or global default) —
  /// drives the bottom action bar's rotation icon.
  final ReaderOrientation orientation;
  final ReaderBackground background;
  final ValueChanged<int> onJumpToChapter;
  final ValueChanged<ReadingMode> onChangeMode;
  final ValueChanged<ReaderOrientation?> onChangeOrientation;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onReachedEnd;

  @override
  ConsumerState<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends ConsumerState<_ReaderBody> {
  bool _chromeVisible = true;
  int _currentPage = 0;
  int _totalPages = 0;
  // Resolved page image handles, threaded up from the active page list so
  // the long-press "Set as cover" action can rebuild the current page's
  // provider and capture its bytes. Null until the pages resolve; cleared
  // when the loaded chapter changes.
  List<_PageRef>? _pageRefs;
  // Used by the paged-mode slider to drive the underlying PageController.
  // Bumped whenever the user moves the slider; the viewport reads it via
  // [_ViewportRequest] and animates to the new index.
  int _seekRequestId = 0;
  int _seekTarget = 0;
  // Whether the pending paged seek (keyed by [_seekRequestId]) should animate
  // the page turn. Page-turn navigation (tap zones / volume keys) animates
  // when `pref_enable_transitions` is on; slider drags always jump instantly.
  bool _seekAnimate = false;
  // Continuous-mode volume-key scrolling. `_scrollTick` ticks per press; the
  // webtoon viewport watches it and scrolls roughly one screen in
  // `_scrollForward`'s direction.
  int _scrollTick = 0;
  bool _scrollForward = true;
  // Last volume-key interception state pushed to the native channel, so we
  // only call across the platform boundary when it actually changes.
  bool _volumeKeysApplied = false;
  // Set once the user taps away the tap-zone guide overlay this session,
  // so it never re-appears even before the (async) pref write lands.
  bool _navOverlayDismissed = false;
  // Guards the "reaching the last page auto-marks the chapter read" action
  // (Mihon parity) so it fires at most once per chapter session. Reset when
  // the loaded chapter changes via didUpdateWidget.
  bool _autoMarkedRead = false;
  // Auto-hide timer for the chrome overlay. Re-armed each time the
  // chrome becomes visible (initial state + every toggle-to-visible).
  // `null` means either auto-hide is disabled (delay = 0) or the
  // chrome is currently hidden.
  Timer? _autoHideTimer;
  // E-Ink page-change flash. `_flashColor` is non-null while the flash
  // overlay is being painted; `_flashTimer` clears it after the
  // configured duration. `_pagesSinceFlash` counts page changes so the
  // flash only fires every Nth (interval) page.
  Color? _flashColor;
  Timer? _flashTimer;
  int _pagesSinceFlash = 0;
  // Transient label flashed centre-screen (Mihon's reader toasts): the
  // reading-mode name on chapter open / mode change (gated by
  // `pref_show_reading_mode`), plus crop-border / orientation toggles.
  // `_overlayText` keeps the last label so it stays painted while the
  // overlay fades out.
  bool _overlayVisible = false;
  String _overlayText = '';
  Timer? _overlayTimer;
  // Live zoom handles per source page (Mihon navigateToPan): tap-nav asks
  // the current page to pan before turning.
  final _ZoomRegistry _zoomRegistry = _ZoomRegistry();
  // Web URL of the open chapter, resolved async through the source
  // (Kotlin's `assistUrl`). Gates the top-bar overflow actions.
  String? _chapterUrl;

  @override
  void initState() {
    super.initState();
    // Chrome starts visible — arm the initial countdown so the reader
    // settles into a clean view if the user doesn't tap anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _armAutoHide();
        _flashReadingMode();
      }
    });
    ReaderVolumeKeys.setListener(_onVolumeKey);
    _zoomRegistry.onReachedLastSlot = _onReachedLastSlot;
    _resolveChapterUrl();
  }

  /// Briefly show the active reading-mode label over the page. Mihon flashes
  /// this when the viewer is (re)created — on chapter open and on a mode
  /// change — when `pref_show_reading_mode` is on.
  void _flashReadingMode() {
    if (!ref.read(readerShowReadingModeProvider)) return;
    _flashLabel(widget.mode.label);
  }

  /// Flash an arbitrary label centre-screen for ~2s (Mihon's
  /// `menuToggleToast`, used for crop-border and orientation toggles).
  void _flashLabel(String label) {
    setState(() {
      _overlayText = label;
      _overlayVisible = true;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  @override
  void didUpdateWidget(covariant _ReaderBody old) {
    super.didUpdateWidget(old);
    // A new chapter was loaded into the same reader: re-arm the auto-mark
    // guard and reset the page counters so the previous chapter's tail
    // doesn't carry over.
    if (widget.data.chapter.id != old.data.chapter.id) {
      _autoMarkedRead = false;
      _downloadedAhead = false;
      _currentPage = 0;
      _totalPages = 0;
      _pageRefs = null;
      _flashReadingMode();
      _resolveChapterUrl();
    } else if (widget.mode != old.mode) {
      // Reading mode switched on the same chapter — re-flash the label.
      _flashReadingMode();
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _flashTimer?.cancel();
    _overlayTimer?.cancel();
    ReaderVolumeKeys.setListener(null);
    if (_volumeKeysApplied) ReaderVolumeKeys.setEnabled(false);
    super.dispose();
  }

  /// Handle a hardware volume-key press relayed from the host activity.
  /// [up] is true for volume-up. Default mapping: volume-down advances
  /// (forward), volume-up goes back; the invert pref swaps it. Paged modes
  /// turn a page (falling through to the adjacent chapter at a boundary);
  /// continuous modes scroll roughly one screen.
  void _onVolumeKey(bool up) {
    if (!mounted) return;
    var forward = !up;
    if (ref.read(readerVolumeKeysInvertedProvider)) forward = !forward;
    if (widget.mode.isPaged) {
      _navigatePage(forward: forward);
    } else {
      setState(() {
        _scrollForward = forward;
        _scrollTick++;
      });
    }
  }

  /// Cache the resolved page handles reported by the active page list so
  /// the "Set as cover" action can find the current page's image. No
  /// setState — this doesn't affect what's currently painted.
  void _onPagesResolved(List<_PageRef> refs) {
    _pageRefs = refs;
    // Warm the pages after the resume point once layout settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAhead(_currentPage);
    });
  }

  /// Resolve the current page to PNG bytes through the same provider the
  /// viewer used ([SourceImage.providerFor], so network / file / archive /
  /// SAF all work). Kotlin hands the original stream around; re-encoding the
  /// decoded frame is the uniform equivalent here.
  Future<Uint8List> _currentPageBytes() async {
    final refs = _pageRefs;
    if (refs == null || _currentPage < 0 || _currentPage >= refs.length) {
      throw StateError("This page isn't ready yet.");
    }
    final ref0 = refs[_currentPage];
    final provider = SourceImage.providerFor(ref0.url, headers: ref0.headers);
    final bytes = await encodeImageProviderToPng(provider);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('image encode produced no bytes');
    }
    return bytes;
  }

  /// Resolve the chapter's web URL through the source (Kotlin resolves
  /// `assistUrl` the same way, async, whenever new chapters are set). Null
  /// hides the top-bar WebView/browser/share overflow — local source,
  /// uninstalled extension, or no producible web URL.
  Future<void> _resolveChapterUrl() async {
    final source = widget.data.source;
    String? url;
    if (source != null) {
      try {
        url = await source.getChapterUrl(
          SourceChapter(
            url: widget.data.chapter.url,
            name: widget.data.chapter.name,
          ),
        );
      } catch (_) {
        url = null;
      }
    }
    if (mounted && url != _chapterUrl) {
      setState(() => _chapterUrl = url);
    }
  }

  /// Mihon `generateFilename`: "title - chapter name - pageNumber",
  /// filename-sanitised.
  String _pageFilename() {
    final base = ReaderImageActions.buildValidFilename(
      '${widget.data.manga.title} - ${widget.data.chapter.name}',
    );
    return '$base - ${_currentPage + 1}';
  }

  /// Capture the current page's bitmap and store it as [data.manga]'s custom
  /// cover (Mihon's reader "Set as cover"). Gated on the manga being local or
  /// in the library — a cover for a non-library entry would be orphaned
  /// (Kotlin's AddToLibraryFirst result). `cover_last_modified` is bumped so
  /// every cover surface repaints.
  Future<void> _setCurrentPageAsCover() async {
    final messenger = ScaffoldMessenger.of(context);
    final manga = widget.data.manga;
    if (!manga.favorite && manga.source != 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please add the entry to your library before doing this'),
        ),
      );
      return;
    }
    try {
      final bytes = await _currentPageBytes();
      await ref.read(coverCacheProvider).setCustomCover(manga.id, bytes);
      await ref.read(mangaRepositoryProvider).bumpCoverLastModified(manga.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover updated')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t set cover: $e')),
      );
    }
  }

  /// Kotlin `SetCoverDialog`: confirm before overwriting the cover.
  Future<void> _confirmSetAsCover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Use this image as cover art?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _setCurrentPageAsCover();
  }

  Future<void> _shareCurrentPage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _currentPageBytes();
      // Mihon `share_page_info`: "%1$s: %2$s, page %3$d".
      await ReaderImageActions.share(
        bytes,
        filename: '${_pageFilename()}.png',
        message: '${widget.data.manga.title}: ${widget.data.chapter.name}, '
            'page ${_currentPage + 1}',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t share page: $e')),
      );
    }
  }

  Future<void> _copyCurrentPage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _currentPageBytes();
      // No success toast — Kotlin relies on the Android 13+ system clip
      // preview, and so do we.
      await ReaderImageActions.copyToClipboard(
        bytes,
        filename: '${_pageFilename()}.png',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t copy page: $e')),
      );
    }
  }

  Future<void> _saveCurrentPage() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _currentPageBytes();
      await ReaderImageActions.saveToPictures(
        bytes,
        displayName: _pageFilename(),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Picture saved')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t save page: $e')),
      );
    }
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

  /// Paint a full-screen E-Ink flash on page change when enabled, every
  /// `interval` pages, for `duration` ms. Mirrors Mihon's
  /// `pref_reader_flash` clearing the e-paper ghost. For [whiteBlack] the
  /// flash shows white for the first half then black for the second.
  void _maybeFlash() {
    if (!ref.read(readerFlashOnPageChangeProvider)) return;
    final interval = ref.read(readerFlashIntervalProvider).clamp(1, 10);
    _pagesSinceFlash++;
    if (_pagesSinceFlash < interval) return;
    _pagesSinceFlash = 0;

    final durationMs = ref.read(readerFlashDurationProvider).clamp(1, 5000);
    final flashColor = ref.read(readerFlashColorProvider);
    _flashTimer?.cancel();

    switch (flashColor) {
      case ReaderFlashColor.black:
        _showFlash(Colors.black, durationMs);
      case ReaderFlashColor.white:
        _showFlash(Colors.white, durationMs);
      case ReaderFlashColor.whiteBlack:
        // White for the first half, then black for the second half.
        final half = (durationMs / 2).round().clamp(1, durationMs);
        _showFlash(Colors.white, half);
        _flashTimer = Timer(Duration(milliseconds: half), () {
          if (mounted) _showFlash(Colors.black, half);
        });
    }
  }

  void _showFlash(Color color, int durationMs) {
    setState(() => _flashColor = color);
    _flashTimer?.cancel();
    _flashTimer = Timer(Duration(milliseconds: durationMs), () {
      if (mounted) setState(() => _flashColor = null);
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

  /// Pre-decode the next two pages so the swipe lands on an already-decoded
  /// frame (Mihon's HttpPageLoader preloads ahead; PageView's implicit ±1
  /// only *builds* the neighbour — the decode itself still happened at
  /// swipe time, which is exactly when it stutters). The provider chain
  /// matches the displayed one (crop included) so the cache key is shared.
  void _precacheAhead(int page) {
    if (!widget.mode.isPaged || !mounted) return;
    final refs = _pageRefs;
    if (refs == null) return;
    final crop = ref.read(readerCropBordersProvider);
    for (var i = page + 1; i <= page + 2 && i < refs.length; i++) {
      final r = refs[i];
      ImageProvider provider =
          SourceImage.providerFor(r.url, headers: r.headers);
      if (crop) provider = CropBordersImageProvider(provider);
      unawaited(precacheImage(provider, context));
    }
  }

  void _onPageChanged(int page) {
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      _maybeFlash();
    }
    // The transition page reports index == _totalPages; progress persists
    // the last REAL page (Kotlin doesn't store transitions either).
    final lastReal = _totalPages > 0 ? _totalPages - 1 : 0;
    widget.onPageChanged(page.clamp(0, lastReal));
    _precacheAhead(page);
    _maybeDownloadAhead(page);
  }

  /// Reaching the last REAL display slot marks the chapter read (Mihon
  /// parity) — fired from the display layer (see [_ZoomRegistry.
  /// onReachedLastSlot]) rather than the deduped source-page callback, so
  /// the second half of a split final spread still triggers it. Guarded so
  /// paging back and forth past the end doesn't re-fire the tracker push.
  void _onReachedLastSlot() {
    if (!_autoMarkedRead && _totalPages > 0) {
      _autoMarkedRead = true;
      widget.onReachedEnd();
    }
  }

  // Whether this reader instance has already triggered a download-ahead pass
  // for the current chapter. Mirrors Mihon's per-chapter single-shot: once we
  // cross the 25% threshold and enqueue, we don't re-enqueue on every later
  // page turn within the same chapter.
  bool _downloadedAhead = false;

  /// Mihon parity (`ReaderViewModel.downloadNextChapters`): once the reader
  /// passes 25% of a *downloaded* chapter in a *favorited* manga, pre-download
  /// the next [autoDownloadWhileReadingProvider] unread chapters — but only if
  /// the immediately-next chapter is already downloaded (jank avoidance).
  void _maybeDownloadAhead(int page) {
    if (_downloadedAhead) return;
    final amount = ref.read(autoDownloadWhileReadingProvider);
    if (amount == 0) return;
    if (!widget.data.manga.favorite) return;
    if (_totalPages <= 0) return;
    if ((page + 1) / _totalPages <= 0.25) return;
    // Current chapter must itself be downloaded.
    if (widget.data.localPagePaths == null) return;
    final next = widget.data.nextChapter;
    if (next == null) return;
    _downloadedAhead = true;
    unawaited(_downloadAhead(next, amount));
  }

  Future<void> _downloadAhead(Chapter next, int amount) async {
    final manga = widget.data.manga;
    final downloadRepo = ref.read(downloadRepositoryProvider);
    // Only proceed if the immediately-next chapter is already on disk, so the
    // pager doesn't stutter pulling its pages mid-read (Mihon's guard).
    final nextDownloaded =
        await downloadRepo.isDownloaded(manga.source, manga.id, next.id);
    if (!nextDownloaded) return;
    final siblings = widget.data.siblings;
    final startIdx = siblings.indexWhere((c) => c.id == next.id);
    if (startIdx < 0) return;
    // Enqueue the next `amount` *unread* chapters from the next one onward,
    // in reading order. `enqueue` itself dedupes and skips ones already
    // downloaded, so we don't filter those here.
    final toDownload = <Chapter>[];
    for (var i = startIdx;
        i < siblings.length && toDownload.length < amount;
        i++) {
      if (!siblings[i].read) toDownload.add(siblings[i]);
    }
    for (final c in toDownload) {
      await downloadRepo.enqueue(manga, c);
    }
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

  void _seekTo(int page, {bool animate = false}) {
    setState(() {
      _currentPage = page;
      _seekTarget = page;
      _seekAnimate = animate;
      _seekRequestId++;
    });
  }

  /// Chrome bar colour — Kotlin's `surfaceColorAtElevation(3.dp)` with
  /// 0.9 (dark) / 0.95 (light) alpha, shared by the top bar, the chapter
  /// navigator's buttons/pill and the bottom action bar.
  Color _barColor(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ElevationOverlay.applySurfaceTint(
      scheme.surface,
      scheme.surfaceTint,
      3,
    ).withValues(alpha: theme.brightness == Brightness.dark ? 0.9 : 0.95);
  }

  /// Bottom-bar crop toggle. Kotlin toasts "On"/"Off" via
  /// `menuToggleToast`; we flash the same label centre-screen. Toggles the
  /// active viewer's own pref (pager vs webtoon, like Kotlin).
  void _toggleCropBorders() {
    final provider = widget.mode.isPaged
        ? readerCropBordersProvider
        : readerCropBordersWebtoonProvider;
    final next = !ref.read(provider);
    ref.read(provider.notifier).set(next);
    _flashLabel(next ? 'On' : 'Off');
  }

  /// Bottom-bar reading-mode picker (Kotlin `ReadingModeSelectDialog`).
  /// Writes a per-series override; "Revert to default" clears it. When
  /// `pref_show_reading_mode` is on the mode change itself re-flashes the
  /// label via [didUpdateWidget], so the explicit flash only covers the
  /// pref-off case (Kotlin toasts there too).
  void _showReadingModeSelect() {
    final raw = ReadingMode.fromFlag(widget.data.manga.viewerFlags);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ModeSelectionSheet<ReadingMode>(
        title: 'Reading mode',
        options: [
          for (final m in ReadingMode.values)
            if (m != ReadingMode.defaultMode)
              ModeOption(m, m.label, readingModeIcon(m)),
        ],
        initial: raw == ReadingMode.defaultMode ? widget.mode : raw,
        onUseDefault: raw == ReadingMode.defaultMode
            ? null
            : () {
                widget.onChangeMode(ReadingMode.defaultMode);
                if (!ref.read(readerShowReadingModeProvider)) {
                  _flashLabel('Default');
                }
              },
        onApply: (m) {
          widget.onChangeMode(m);
          if (!ref.read(readerShowReadingModeProvider)) {
            _flashLabel(m.label);
          }
        },
      ),
    );
  }

  /// Bottom-bar orientation picker (Kotlin `OrientationSelectDialog`).
  /// Kotlin always toasts the new orientation's name.
  void _showOrientationSelect() {
    final raw = ReaderOrientation.fromMangaFlags(widget.data.manga.viewerFlags);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ModeSelectionSheet<ReaderOrientation>(
        title: 'Rotation',
        options: [
          for (final o in ReaderOrientation.values)
            ModeOption(o, o.label, readerOrientationIcon(o)),
        ],
        initial: raw ?? widget.orientation,
        onUseDefault: raw == null
            ? null
            : () {
                widget.onChangeOrientation(null);
                _flashLabel('Default');
              },
        onApply: (o) {
          widget.onChangeOrientation(o);
          _flashLabel(o.label);
        },
      ),
    );
  }

  /// Bottom-bar gear button → the three-tab settings sheet (Kotlin
  /// `ReaderSettingsDialog`).
  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReaderSettingsSheet(
        viewerFlags: widget.data.manga.viewerFlags,
        onChangeMode: widget.onChangeMode,
        onChangeOrientation: widget.onChangeOrientation,
      ),
    );
  }

  /// The active tap-zone navigation preset. Mihon keys these separately
  /// for the paged (pager) and continuous (webtoon) viewers; we follow
  /// the same split so each viewer honours its own preset.
  ReaderNavMode get _navMode => widget.mode.isPaged
      ? ref.read(readerNavModePagerProvider)
      : ref.read(readerNavModeWebtoonProvider);

  /// Handle a tap on the page viewport. Resolves the tap to one of
  /// Mihon's navigation regions for the active preset (ported from
  /// `ViewerNavigation`): PREV/NEXT step a page (falling through to the
  /// adjacent chapter at a boundary), LEFT/RIGHT step direction-relative,
  /// and MENU toggles the chrome. Continuous modes scroll instead of
  /// paging for the page-step regions.
  void _handleViewportTap(TapUpDetails details, Size size) {
    final tapNav = ref.read(readerTapToNavigateProvider);
    final navMode = _navMode;
    if (!tapNav ||
        navMode == ReaderNavMode.disabled ||
        size.width <= 0 ||
        size.height <= 0) {
      _toggleChrome();
      return;
    }
    final nx = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
    final ny = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
    var region = navRegionAt(
      navMode,
      nx,
      ny,
      horizontal: widget.mode.isPaged && widget.mode.isHorizontal,
    );
    // Apply the user's invert pref (horizontal axis) — flips PREV/NEXT and
    // LEFT/RIGHT. Mirrors Mihon's TappingInvertMode applied to regions.
    if (ref.read(readerTapNavigateInvertProvider)) {
      region = _invertRegion(region);
    }
    switch (region) {
      case NavRegion.menu:
        _toggleChrome();
      case NavRegion.prev:
        _navigateRegion(forward: false);
      case NavRegion.next:
        _navigateRegion(forward: true);
      case NavRegion.left:
        // Move-left: previous in LTR, next in RTL.
        _navigateRegion(forward: widget.mode == ReadingMode.rightToLeft);
      case NavRegion.right:
        // Move-right: next in LTR, previous in RTL.
        _navigateRegion(forward: widget.mode != ReadingMode.rightToLeft);
    }
  }

  NavRegion _invertRegion(NavRegion region) {
    switch (region) {
      case NavRegion.prev:
        return NavRegion.next;
      case NavRegion.next:
        return NavRegion.prev;
      case NavRegion.left:
        return NavRegion.right;
      case NavRegion.right:
        return NavRegion.left;
      case NavRegion.menu:
        return NavRegion.menu;
    }
  }

  /// Long-press page actions sheet. Mihon's `reader_long_tap` gates this:
  /// when off, a long press does nothing. The full Mihon sheet offers
  /// set-as-cover / share / save; those page-bitmap actions aren't wired
  /// into this viewer yet, so the sheet currently exposes the chapter-level
  /// actions available here (parent can extend with page export later).
  /// Long-press page-actions sheet — Kotlin `ReaderPageActionsDialog`: a row
  /// of four equal-width action buttons (Set as cover / Copy to clipboard /
  /// Share / Save).
  void _showPageActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            children: [
              _PageActionButton(
                icon: Icons.photo_outlined,
                label: 'Set as cover',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmSetAsCover();
                },
              ),
              _PageActionButton(
                icon: Icons.content_copy_outlined,
                label: 'Copy to clipboard',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copyCurrentPage();
                },
              ),
              _PageActionButton(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _shareCurrentPage();
                },
              ),
              _PageActionButton(
                icon: Icons.save_outlined,
                label: 'Save',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _saveCurrentPage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Page-step in paged modes; scroll one screen in continuous modes.
  void _navigateRegion({required bool forward}) {
    if (widget.mode.isPaged) {
      _navigatePage(forward: forward);
    } else {
      setState(() {
        _scrollForward = forward;
        _scrollTick++;
      });
    }
  }

  /// Turn one page in [forward] direction, or jump to the adjacent
  /// chapter when stepping past either end of the current chapter. With
  /// the chapter-transition page enabled, the index one past the last
  /// page is the transition itself; stepping forward from there does
  /// the chapter jump.
  void _navigatePage({required bool forward}) {
    // Mihon navigateToPan: a zoomed page consumes navigation steps as pans
    // until its edge is reached.
    if (widget.mode.isPaged && ref.read(readerNavigateToPanProvider)) {
      final handle = _zoomRegistry[_currentPage];
      if (handle != null && handle.panTowards(forward: forward)) return;
    }
    // Step in DISPLAY-slot space via the live pager so both halves of a
    // split spread (and the transition page) are visited — stepping source
    // indices used to skip the second half. False at either end falls
    // through to the chapter jump below.
    final stepped = _zoomRegistry.stepPage?.call(
          forward: forward,
          animate: ref.read(readerPageTransitionsProvider),
        ) ??
        false;
    if (stepped) return;
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
    final showPageNumber = ref.watch(readerShowPageNumberProvider);
    // Crop borders is a per-viewer pref (Kotlin: `crop_borders` for the
    // pager, `crop_borders_webtoon` for the continuous viewer).
    final cropEnabled = widget.mode.isPaged
        ? ref.watch(readerCropBordersProvider)
        : ref.watch(readerCropBordersWebtoonProvider);
    final barColor = _barColor(context);
    // Chapter transition page (Kotlin ChapterTransition, gated by
    // `always_show_chapter_transition`): an info page after the last page —
    // "Finished" + what's next — that swiping/tapping forward from triggers
    // the chapter jump.
    final transitionPage = ref.watch(readerAlwaysShowTransitionProvider)
        ? _ChapterTransitionPage(
            finishedTitle: data.chapter.name.isEmpty
                ? 'Chapter ${data.chapter.chapterNumber}'
                : data.chapter.name,
            nextTitle: next == null
                ? null
                : (next.name.isEmpty
                    ? 'Chapter ${next.chapterNumber}'
                    : next.name),
            textColor: widget.background
                .resolveOnColor(Theme.of(context).brightness),
            onNextChapter:
                next == null ? null : () => widget.onJumpToChapter(next.id),
          )
        : null;
    final grayscale = ref.watch(readerGrayscaleProvider);
    final invert = ref.watch(readerInvertedColorsProvider);
    // Paged image scale type (Mihon `pref_image_scale_type_key`). The
    // continuous webtoon viewer always fits width regardless.
    final fit = ref.watch(readerImageScaleTypeProvider).boxFit;
    // Full ARGB colour filter (Mihon `color_filter*`). Only painted when
    // the master toggle is on and the stored colour isn't transparent.
    final colorFilterEnabled = ref.watch(readerColorFilterEnabledProvider);
    final colorFilterColor =
        ref.watch(readerColorFilterValueProvider.notifier).color;
    final colorFilterBlend =
        ref.watch(readerColorFilterModeProvider).blendMode;
    final sidePaddingPct =
        ref.watch(readerWebtoonSidePaddingProvider).clamp(0, 25);

    // Volume-key navigation is intercepted natively only while the reader is
    // open AND the chrome is hidden — matching Mihon, which leaves the keys
    // to their normal volume function whenever the reader menu is visible.
    // Syncing here means a pref change or a chrome toggle (both rebuild) is
    // picked up automatically; we only cross the platform boundary on change.
    // One-time tap-zone guide overlay (Mihon's "new user" navigation hint).
    // Only meaningful where the tap zones are actually live: paged modes
    // with tap-to-navigate on. Tapping it through dismisses + persists off.
    final showNavOverlay = !_navOverlayDismissed &&
        widget.mode.isPaged &&
        ref.watch(readerTapToNavigateProvider) &&
        ref.watch(readerShowNavOverlayProvider);

    final wantVolumeKeys =
        ref.watch(readerVolumeKeysProvider) && !_chromeVisible;
    if (wantVolumeKeys != _volumeKeysApplied) {
      _volumeKeysApplied = wantVolumeKeys;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ReaderVolumeKeys.setEnabled(wantVolumeKeys);
      });
    }

    Widget viewport = _ReaderViewport(
      data: data,
      mode: widget.mode,
      fit: fit,
      sidePaddingFraction: sidePaddingPct / 100,
      cropBorders: cropEnabled,
      // Rotate-to-fit applies to the paged viewer only (Mihon parity); the
      // continuous webtoon viewer keeps its own (unimplemented) variant.
      rotateToFit: widget.mode.isPaged &&
          ref.watch(readerDualPageRotateProvider),
      rotateInvert: ref.watch(readerDualPageRotateInvertProvider),
      onPageChanged: _onPageChanged,
      onTotalChanged: _onTotalChanged,
      onPagesResolved: _onPagesResolved,
      seekRequest: _ViewportSeekRequest(
        requestId: _seekRequestId,
        target: _seekTarget,
        animate: _seekAnimate,
        scrollTick: _scrollTick,
        scrollForward: _scrollForward,
      ),
      transition: transitionPage,
      zoomRegistry: _zoomRegistry,
    );
    // Page-art colour adjustments. Applied to the page viewport only (not
    // the chrome) by wrapping before the gesture/Stack layers. Greyscale,
    // invert and the full colour filter compose by nesting ColorFiltered
    // layers. The colour filter blends the stored ARGB tint over the art
    // with the chosen blend mode (Mihon `color_filter_mode`).
    if (colorFilterEnabled && colorFilterColor != null) {
      viewport = ColorFiltered(
        colorFilter: ColorFilter.mode(colorFilterColor, colorFilterBlend),
        child: viewport,
      );
    }
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
                  _handleViewportTap(d, MediaQuery.sizeOf(context)),
              onLongPress: ref.watch(readerLongTapProvider)
                  ? () => _showPageActions(context)
                  : null,
              child: viewport,
            ),
          ),
          // (Colour filter is applied to the viewport above via
          // ColorFiltered so it blends per-pixel with the page art.)
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
                child: Material(
                  color: barColor,
                  child: _ReaderHeader(
                    manga: data.manga,
                    chapter: data.chapter,
                    chapterUrl: _chapterUrl,
                  ),
                ),
              ),
            ),
          ),
          // Always-visible page indicator (Mihon's PageIndicatorText sits
          // behind the menu, drawn in the reader-background contrast color).
          if (showPageNumber)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _PageIndicator(
                  // Clamped: the transition page isn't a numbered page.
                  current: _currentPage.clamp(0, _totalPages > 0 ? _totalPages - 1 : 0),
                  total: _totalPages,
                  color: widget.background
                      .resolveOnColor(Theme.of(context).brightness),
                ),
              ),
            ),
          // Bottom chrome: chapter navigator + bottom action bar
          // (Mihon ReaderAppBars bottom Column, spacedBy 8).
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ChapterNavigator(
                      isRtl: widget.mode == ReadingMode.rightToLeft,
                      onPreviousChapter: prev == null
                          ? null
                          : () => widget.onJumpToChapter(prev.id),
                      onNextChapter: next == null
                          ? null
                          : () => widget.onJumpToChapter(next.id),
                      currentPage:
                          _currentPage.clamp(0, _totalPages > 0 ? _totalPages - 1 : 0),
                      totalPages: _totalPages,
                      showSlider: widget.mode.isPaged,
                      onPageIndexChange: _seekTo,
                      barColor: barColor,
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: barColor,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              tooltip: 'Reading mode',
                              icon: Icon(readingModeIcon(widget.mode)),
                              onPressed: _showReadingModeSelect,
                            ),
                            IconButton(
                              tooltip: 'Rotation',
                              icon: Icon(
                                readerOrientationIcon(widget.orientation),
                              ),
                              onPressed: _showOrientationSelect,
                            ),
                            IconButton(
                              tooltip: 'Crop borders',
                              icon: Icon(
                                Icons.crop,
                                color: cropEnabled
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              onPressed: _toggleCropBorders,
                            ),
                            IconButton(
                              tooltip: 'Settings',
                              icon: const Icon(Icons.settings_outlined),
                              onPressed: _showSettingsSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Reading-mode label, flashed centre-screen on chapter open / mode
          // change when `pref_show_reading_mode` is on. Fades out via the
          // timer in [_flashReadingMode]; IgnorePointer so it never eats taps.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _overlayVisible ? 1 : 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _overlayText,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // E-Ink page-change flash. Painted on top of everything for the
          // configured duration to clear e-paper ghosting. IgnorePointer
          // so it never eats a tap mid-flash.
          if (_flashColor != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: _flashColor!),
              ),
            ),
          // Tap-zone guide overlay. Sits on top of everything (including
          // chrome) and swallows the first tap to dismiss itself.
          if (showNavOverlay)
            Positioned.fill(
              child: _NavZoneOverlay(
                mode: widget.mode,
                inverted: ref.watch(readerTapNavigateInvertProvider),
                onDismiss: () {
                  setState(() => _navOverlayDismissed = true);
                  ref.read(readerShowNavOverlayProvider.notifier).set(false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// A one-shot translucent guide drawn over the reader the first time a
/// paged chapter opens, illustrating which screen third turns the page
/// forward, which goes back, and which toggles the menu. Mirrors Mihon's
/// `ReaderNavigationOverlayView`. Tapping anywhere dismisses it.
class _NavZoneOverlay extends StatelessWidget {
  const _NavZoneOverlay({
    required this.mode,
    required this.inverted,
    required this.onDismiss,
  });

  final ReadingMode mode;
  final bool inverted;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Which edge advances. Right advances by default; RTL reading and the
    // invert pref each flip it — matching `_handleViewportTap`.
    var rightAdvances = true;
    if (mode == ReadingMode.rightToLeft) rightAdvances = !rightAdvances;
    if (inverted) rightAdvances = !rightAdvances;

    const next = _NavZoneRegion(
      color: Color(0x668BC34A),
      icon: Icons.chevron_right,
      label: 'Next',
    );
    const prev = _NavZoneRegion(
      color: Color(0x66FFC107),
      icon: Icons.chevron_left,
      label: 'Previous',
    );
    const menu = _NavZoneRegion(
      color: Color(0x66607D8B),
      icon: Icons.menu,
      label: 'Menu',
    );

    return GestureDetector(
      onTap: onDismiss,
      child: Row(
        children: [
          Expanded(child: rightAdvances ? prev : next),
          const Expanded(child: menu),
          Expanded(child: rightAdvances ? next : prev),
        ],
      ),
    );
  }
}

class _NavZoneRegion extends StatelessWidget {
  const _NavZoneRegion({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 48),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
  const _ViewportSeekRequest({
    required this.requestId,
    required this.target,
    this.animate = false,
    this.scrollTick = 0,
    this.scrollForward = true,
  });

  /// Monotonic id that ticks every time the user drags the slider — the
  /// viewport listens for this to know whether the request is fresh, since
  /// we may emit two requests with the same `target` index back-to-back.
  final int requestId;
  final int target;

  /// Whether the paged viewport should animate to [target] (page-turn with
  /// transitions on) rather than jump instantly (slider drag).
  final bool animate;

  /// Monotonic id that ticks every time the volume keys ask the continuous
  /// (webtoon) viewport to scroll by roughly one screen. Paged viewers
  /// ignore it; the slider-driven [requestId] handles their seeks instead.
  final int scrollTick;

  /// Direction of the pending [scrollTick]: true scrolls down (forward).
  final bool scrollForward;
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.current,
    required this.total,
    required this.color,
  });

  final int current;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '${current + 1} / $total',
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

/// One equal-width entry in the page-actions sheet — port of Kotlin's
/// `ActionButton` (icon stacked over a small centred label).
class _PageActionButton extends StatelessWidget {
  const _PageActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirror of Mihon's `ChapterNavigator`: prev/next chapter FilledIconButtons
/// flanking a rounded pill with the page slider. The row is always laid out
/// LTR; for an R2L pager the pill's content direction flips and the left
/// button becomes "next chapter" — matching the Kotlin composable.
class _ChapterNavigator extends StatelessWidget {
  const _ChapterNavigator({
    required this.isRtl,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.currentPage,
    required this.totalPages,
    required this.showSlider,
    required this.onPageIndexChange,
    required this.barColor,
  });

  final bool isRtl;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final int currentPage;
  final int totalPages;
  final bool showSlider;
  final ValueChanged<int> onPageIndexChange;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: barColor,
      disabledBackgroundColor: barColor,
      foregroundColor: scheme.onSurface,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
    );
    // Match Kotlin: left button skips backward in reading order, so on an
    // R2L pager it is the *next* chapter.
    final onLeft = isRtl ? onNextChapter : onPreviousChapter;
    final onRight = isRtl ? onPreviousChapter : onNextChapter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton.filled(
            style: buttonStyle,
            tooltip: isRtl ? 'Next chapter' : 'Previous chapter',
            icon: const Icon(Icons.skip_previous_outlined),
            onPressed: onLeft,
          ),
          Expanded(
            child: showSlider && totalPages > 1
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Directionality(
                        textDirection:
                            isRtl ? TextDirection.rtl : TextDirection.ltr,
                        child: Row(
                          children: [
                            // Transparent total reserves width so the label
                            // doesn't jiggle as the page count grows.
                            Stack(
                              alignment: AlignmentDirectional.centerEnd,
                              children: [
                                Text(
                                  '$totalPages',
                                  style: const TextStyle(
                                    color: Colors.transparent,
                                  ),
                                ),
                                Text('${currentPage + 1}'),
                              ],
                            ),
                            Expanded(
                              child: Slider(
                                min: 1,
                                max: totalPages.toDouble(),
                                divisions: totalPages - 1,
                                value: (currentPage + 1)
                                    .clamp(1, totalPages)
                                    .toDouble(),
                                onChanged: (v) {
                                  final target = v.round() - 1;
                                  if (target != currentPage) {
                                    onPageIndexChange(target);
                                  }
                                },
                              ),
                            ),
                            Text('$totalPages'),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton.filled(
            style: buttonStyle,
            tooltip: isRtl ? 'Previous chapter' : 'Next chapter',
            icon: const Icon(Icons.skip_next_outlined),
            onPressed: onRight,
          ),
        ],
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
    required this.cropBorders,
    required this.rotateToFit,
    required this.rotateInvert,
    required this.onPageChanged,
    required this.onTotalChanged,
    required this.onPagesResolved,
    required this.seekRequest,
    this.transition,
    this.zoomRegistry,
  });

  final _ReaderData data;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final bool cropBorders;
  final bool rotateToFit;
  final bool rotateInvert;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalChanged;
  final ValueChanged<List<_PageRef>> onPagesResolved;
  final _ViewportSeekRequest seekRequest;

  /// Trailing chapter-transition page, threaded through to [_PagesView].
  final Widget? transition;
  final _ZoomRegistry? zoomRegistry;

  @override
  Widget build(BuildContext context) {
    if (data.localPagePaths != null) {
      // Report total synchronously — local pages are already enumerated.
      onTotalChanged(data.localPagePaths!.length);
      return _LocalPageList(
        // In-place chapter navigation swaps the chapter under this same
        // element (see _ReaderBody.didUpdateWidget). Key the subtree by
        // chapter so the viewer (controllers, positions) starts fresh
        // instead of carrying the previous chapter's state.
        key: ValueKey('local-${data.chapter.id}'),
        paths: data.localPagePaths!,
        mode: mode,
        fit: fit,
        sidePaddingFraction: sidePaddingFraction,
        cropBorders: cropBorders,
        rotateToFit: rotateToFit,
        rotateInvert: rotateInvert,
        initialPage: data.chapter.lastPageRead,
        onPageChanged: onPageChanged,
        onPagesResolved: onPagesResolved,
        seekRequest: seekRequest,
        transition: transition,
        zoomRegistry: zoomRegistry,
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
      // Same in-place chapter-swap hazard as above, and worse here:
      // _PageListState fetches its page list once in initState, so a reused
      // element keeps RENDERING THE OLD CHAPTER'S PAGES while progress /
      // mark-read writes target the new chapter id. The key forces a fresh
      // fetch per chapter.
      key: ValueKey('remote-${data.chapter.id}'),
      source: data.source!,
      chapter: data.chapter,
      mode: mode,
      fit: fit,
      sidePaddingFraction: sidePaddingFraction,
      cropBorders: cropBorders,
      rotateToFit: rotateToFit,
      rotateInvert: rotateInvert,
      onPageChanged: onPageChanged,
      onTotalChanged: onTotalChanged,
      onPagesResolved: onPagesResolved,
      seekRequest: seekRequest,
      transition: transition,
      zoomRegistry: zoomRegistry,
    );
  }
}

class _PageList extends StatefulWidget {
  const _PageList({
    super.key,
    required this.source,
    required this.chapter,
    required this.mode,
    required this.fit,
    required this.sidePaddingFraction,
    required this.cropBorders,
    required this.rotateToFit,
    required this.rotateInvert,
    required this.onPageChanged,
    required this.onTotalChanged,
    required this.onPagesResolved,
    required this.seekRequest,
    this.transition,
    this.zoomRegistry,
  });

  final MangaSource source;
  final Chapter chapter;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final bool cropBorders;
  final bool rotateToFit;
  final bool rotateInvert;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalChanged;
  final ValueChanged<List<_PageRef>> onPagesResolved;
  final _ViewportSeekRequest seekRequest;
  final Widget? transition;
  final _ZoomRegistry? zoomRegistry;

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
        // Report total + page handles once we know them. Routed through a
        // post-frame callback because we're inside `build()`.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onTotalChanged(pages.length);
          widget.onPagesResolved([
            for (final page in pages)
              _PageRef(page.imageUrl ?? page.url, page.headers),
          ]);
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
          transition: widget.transition,
          pageUrlOf: (i) => pages[i].imageUrl ?? pages[i].url,
          pageHeadersOf: (i) => pages[i].headers,
          zoomRegistry: widget.zoomRegistry,
          fit: widget.fit,
          itemBuilder: (_, i) {
            final page = pages[i];
            final imageUrl = page.imageUrl ?? page.url;
            return SourceImage(
              url: imageUrl,
              fit: widget.fit,
              headers: page.headers,
              cropBorders: widget.cropBorders,
              rotateToFit: widget.rotateToFit,
              rotateInvert: widget.rotateInvert,
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
    super.key,
    required this.paths,
    required this.mode,
    required this.fit,
    required this.sidePaddingFraction,
    required this.cropBorders,
    required this.rotateToFit,
    required this.rotateInvert,
    required this.initialPage,
    required this.onPageChanged,
    required this.onPagesResolved,
    required this.seekRequest,
    this.transition,
    this.zoomRegistry,
  });

  final List<String> paths;
  final ReadingMode mode;
  final BoxFit fit;
  final double sidePaddingFraction;
  final bool cropBorders;
  final bool rotateToFit;
  final bool rotateInvert;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<List<_PageRef>> onPagesResolved;
  final _ViewportSeekRequest seekRequest;
  final Widget? transition;
  final _ZoomRegistry? zoomRegistry;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const Center(
        child: Text('No pages.', style: TextStyle(color: Colors.white70)),
      );
    }
    // Local pages are already enumerated — report their handles so the
    // "Set as cover" action can reach them (post-frame: we're in `build`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onPagesResolved([for (final path in paths) _PageRef(path, null)]);
    });
    return _PagesView(
      count: paths.length,
      mode: mode,
      sidePaddingFraction: sidePaddingFraction,
      initialPage: initialPage,
      onPageChanged: onPageChanged,
      seekRequest: seekRequest,
      transition: transition,
      pageUrlOf: (i) => paths[i],
      pageHeadersOf: (_) => null,
      zoomRegistry: zoomRegistry,
      fit: fit,
      itemBuilder: (_, i) => SourceImage(
        url: paths[i],
        fit: fit,
        cropBorders: cropBorders,
        rotateToFit: rotateToFit,
        rotateInvert: rotateInvert,
        errorWidget: (_, error) => SizedBox(
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
class _PagesView extends ConsumerStatefulWidget {
  const _PagesView({
    required this.count,
    required this.mode,
    required this.sidePaddingFraction,
    required this.initialPage,
    required this.onPageChanged,
    required this.seekRequest,
    required this.itemBuilder,
    this.transition,
    this.pageUrlOf,
    this.pageHeadersOf,
    this.zoomRegistry,
    this.fit = BoxFit.contain,
  });

  final int count;
  final ReadingMode mode;
  final double sidePaddingFraction;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final _ViewportSeekRequest seekRequest;
  final IndexedWidgetBuilder itemBuilder;

  /// Chapter-transition page (Kotlin `ChapterTransition`): when non-null,
  /// one extra trailing item past the last page — index [count] — renders
  /// it in both viewers. Reported page indices include it, so navigating
  /// forward from it falls through to the next chapter.
  final Widget? transition;

  /// Image locator per page index — feeds the shared aspect-ratio cache
  /// used for webtoon fixed-extent placeholders and the paged viewer's
  /// zoom-start/landscape-zoom initial transform.
  final String? Function(int index)? pageUrlOf;

  /// Per-page HTTP headers, needed when the dual-page splitter builds the
  /// half-page images itself (bypassing [itemBuilder]).
  final Map<String, String>? Function(int index)? pageHeadersOf;

  /// Scale-type fit, so split halves render like whole pages do.
  final BoxFit fit;

  /// Zoom handles keyed by SOURCE page index, owned by the reader body so
  /// tap-navigation can pan a zoomed page before turning it (Mihon
  /// navigateToPan).
  final _ZoomRegistry? zoomRegistry;

  /// Total item count including the trailing transition page.
  int get itemCount => count + (transition != null ? 1 : 0);

  @override
  ConsumerState<_PagesView> createState() => _PagesViewState();
}

/// Mutable map of live [_ZoomablePageState]s keyed by source page index —
/// the bridge that lets [_ReaderBodyState._navigatePage] ask the current
/// page to pan before falling through to a page turn.
class _ZoomRegistry {
  final Map<int, _ZoomablePageState> _handles = {};

  /// Set by the live [_PagesViewState]: steps the pager one DISPLAY slot
  /// (so both halves of a split spread are visited — stepping source
  /// indices skipped the second half). Returns false at either end so the
  /// caller falls through to the chapter jump.
  bool Function({required bool forward, required bool animate})? stepPage;

  /// Fired by the live [_PagesViewState] when the viewer lands on the last
  /// REAL display slot (the last page, or the second half of a split final
  /// spread — NOT the trailing transition page). Drives end-of-chapter
  /// auto-mark: the source-page `onPageChanged` dedups, so the deduped
  /// second half never re-reports and a gate polled there would never see
  /// the true state. A push from the display layer can't be deduped away.
  VoidCallback? onReachedLastSlot;

  void register(int index, _ZoomablePageState state) =>
      _handles[index] = state;

  void unregister(int index, _ZoomablePageState state) {
    if (_handles[index] == state) _handles.remove(index);
  }

  _ZoomablePageState? operator [](int index) => _handles[index];
}

/// Decoded width/height ratio per page locator, shared across viewers.
/// Populated as pages decode; lets webtoon items reserve their real extent
/// on revisit (no layout shift), powers offset↔index math for progress and
/// resume, and tells the paged viewer whether a page is a wide spread.
/// Bounded (insertion-order eviction) so a long session doesn't grow it
/// forever — same idea as the crop-rect LRU.
final Map<String, double> _pageAspectCache = {};
const int _pageAspectCacheCap = 2048;

void _cachePageAspect(String url, double aspect) {
  _pageAspectCache.remove(url);
  _pageAspectCache[url] = aspect;
  while (_pageAspectCache.length > _pageAspectCacheCap) {
    _pageAspectCache.remove(_pageAspectCache.keys.first);
  }
}

/// Resolve [url]'s decoded aspect into [_pageAspectCache], then [onReady].
/// Piggybacks on the image cache — by the time this runs for a visible page
/// the decode is shared with the displayed image.
void _resolvePageAspect(
  String url,
  Map<String, String>? headers,
  void Function(double aspect) onReady,
) {
  final cached = _pageAspectCache[url];
  if (cached != null) {
    onReady(cached);
    return;
  }
  final stream = SourceImage.providerFor(url, headers: headers)
      .resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      final aspect = info.image.width / info.image.height;
      _cachePageAspect(url, aspect);
      info.image.dispose();
      stream.removeListener(listener);
      onReady(aspect);
    },
    onError: (_, _) => stream.removeListener(listener),
  );
  stream.addListener(listener);
}

class _PagesViewState extends ConsumerState<_PagesView> {
  PageController? _pageController;
  ScrollController? _scrollController;

  /// Last reported SOURCE page index (display indices are internal).
  int _lastReported = -1;

  /// One display slot per rendered page. `half` is 0 for a whole page,
  /// 1/2 for the first/second half of a split wide page (Mihon
  /// dualPageSplitPaged: a landscape spread renders as two display pages).
  /// Recomputed each build from the aspect cache; null when splitting is
  /// off (1:1 mapping, zero overhead).
  List<({int src, int half})>? _slots;
  String _slotsSignature = '';

  /// Webtoon zoom layer (Mihon WebtoonViewer pinch/double-tap zoom).
  final TransformationController _webtoonZoom = TransformationController();
  TapDownDetails? _webtoonDoubleTapDown;

  /// The display slot currently on screen (paged), kept so a mapping
  /// change can re-anchor onto the SAME half of a split spread.
  ({int src, int half})? _currentSlot;

  int get _displayCount => _slots?.length ?? widget.count;

  int _displayToSource(int display) {
    final slots = _slots;
    if (slots == null) return display;
    if (display >= slots.length) return widget.count; // transition slot
    return slots[display].src;
  }

  int _sourceToDisplay(int source) {
    final slots = _slots;
    if (slots == null) return source;
    if (source >= widget.count) return slots.length; // transition slot
    for (var d = 0; d < slots.length; d++) {
      if (slots[d].src == source) return d;
    }
    return source.clamp(0, slots.length - 1);
  }

  /// Rebuild the display-slot list for the current split pref + aspect
  /// knowledge. Returns true when the mapping changed (caller re-anchors
  /// the PageController so the visible page doesn't shift).
  bool _rebuildSlots({required bool splitWide}) {
    if (!splitWide || !widget.mode.isPaged) {
      final changed = _slots != null;
      _slots = null;
      _slotsSignature = '';
      return changed;
    }
    final slots = <({int src, int half})>[];
    final sig = StringBuffer();
    for (var i = 0; i < widget.count; i++) {
      final url = widget.pageUrlOf?.call(i);
      final aspect = url == null ? null : _pageAspectCache[url];
      if (aspect != null && aspect > 1) {
        slots.add((src: i, half: 1));
        slots.add((src: i, half: 2));
        sig.write('$i,');
      } else {
        slots.add((src: i, half: 0));
        // A page with unknown aspect may later split — but only probe the
        // pages around the reading position: probing everything kicked a
        // full fetch+decode of the ENTIRE chapter the moment split was
        // enabled. The window keeps pace as _lastReported advances.
        if (aspect == null && url != null && (i - _lastReported).abs() <= 3) {
          _resolvePageAspect(url, widget.pageHeadersOf?.call(i), (a) {
            if (mounted && a > 1) setState(() {});
          });
        }
      }
    }
    final signature = sig.toString();
    final changed = _slots == null || signature != _slotsSignature;
    _slots = slots;
    _slotsSignature = signature;
    return changed;
  }

  /// Estimated layout height of page [i] in the continuous list: the real
  /// extent once its aspect is known (cache hit), a generic placeholder
  /// height before first decode. Powers offset↔index mapping so progress
  /// and resume track actual pages instead of a scroll-ratio guess.
  double _estimatedHeight(int i, double contentWidth) {
    final url = widget.pageUrlOf?.call(i);
    final aspect = url == null ? null : _pageAspectCache[url];
    return aspect == null ? 400.0 : contentWidth / aspect;
  }

  double _webtoonContentWidth() {
    final size = MediaQuery.sizeOf(context);
    return size.width * (1 - 2 * widget.sidePaddingFraction);
  }

  double _offsetForIndex(int index) {
    final w = _webtoonContentWidth();
    var offset = 0.0;
    for (var i = 0; i < index && i < widget.count; i++) {
      offset += _estimatedHeight(i, w);
    }
    return offset;
  }

  int _indexForOffset(double pixels) {
    final w = _webtoonContentWidth();
    var cumulative = 0.0;
    for (var i = 0; i < widget.count; i++) {
      cumulative += _estimatedHeight(i, w);
      if (pixels < cumulative) return i;
    }
    return widget.count - 1;
  }

  void _jumpToWebtoonIndex(int index) {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final pos = controller.position;
    controller.jumpTo(_offsetForIndex(index).clamp(0.0, pos.maxScrollExtent));
  }

  @override
  void initState() {
    super.initState();
    final clamped =
        widget.initialPage.clamp(0, (widget.count - 1).clamp(0, widget.count));
    if (widget.mode.isPaged) {
      _rebuildSlots(splitWide: ref.read(readerDualPageSplitProvider));
      _pageController =
          PageController(initialPage: _sourceToDisplay(clamped));
    } else {
      _scrollController = ScrollController();
      // Defer jump until after layout so the viewport has a size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToWebtoonIndex(clamped);
      });
    }
    _lastReported = clamped;
    widget.zoomRegistry?.stepPage = _stepDisplayPage;
  }

  /// Step the pager one DISPLAY slot (visits both halves of split spreads
  /// and the trailing transition page). False at either end — the caller
  /// then jumps chapters.
  bool _stepDisplayPage({required bool forward, required bool animate}) {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return false;
    final current = controller.page?.round() ?? _sourceToDisplay(_lastReported);
    final next = forward ? current + 1 : current - 1;
    final maxIndex =
        _displayCount - 1 + (widget.transition != null ? 1 : 0);
    if (next < 0 || next > maxIndex) return false;
    if (animate) {
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      controller.jumpToPage(next);
    }
    return true;
  }

  /// True when display slot [d] is the last REAL page (excludes the
  /// trailing transition slot at index [_displayCount]).
  bool _isLastRealSlot(int d) => d == _displayCount - 1;

  @override
  void didUpdateWidget(covariant _PagesView old) {
    super.didUpdateWidget(old);
    // Reading mode switched between paged and continuous on a live viewer
    // (Kotlin recreates the whole viewer here): swap in the matching
    // controller, resuming at the last page we reported.
    if (widget.mode.isPaged != old.mode.isPaged) {
      // A viewer swap is a fresh start — don't carry the webtoon zoom
      // transform into (or back out of) paged mode.
      _webtoonZoom.value = Matrix4.identity();
      _pageController?.dispose();
      _scrollController?.dispose();
      _pageController = null;
      _scrollController = null;
      final resume =
          _lastReported.clamp(0, (widget.count - 1).clamp(0, widget.count));
      if (widget.mode.isPaged) {
        _rebuildSlots(splitWide: ref.read(readerDualPageSplitProvider));
        _pageController =
            PageController(initialPage: _sourceToDisplay(resume));
      } else {
        _scrollController = ScrollController();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _jumpToWebtoonIndex(resume);
        });
      }
      return;
    }
    // Slider drove a seek: jump the underlying PageController. Continuous
    // mode has no random-access seek surface — slider only shows in paged
    // mode anyway so this branch is a no-op there. The clamp allows the
    // trailing transition page as a target.
    if (widget.seekRequest.requestId != old.seekRequest.requestId &&
        _pageController != null) {
      final target = _sourceToDisplay(widget.seekRequest.target
          .clamp(0, (widget.itemCount - 1).clamp(0, widget.itemCount)));
      if (widget.seekRequest.animate && _pageController!.hasClients) {
        _pageController!.animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _pageController!.jumpToPage(target);
      }
    }
    // Volume-key scroll in continuous mode: animate by roughly one screen.
    if (widget.seekRequest.scrollTick != old.seekRequest.scrollTick &&
        _scrollController != null &&
        _scrollController!.hasClients) {
      final pos = _scrollController!.position;
      final step = pos.viewportDimension * 0.8;
      final target = (pos.pixels +
              (widget.seekRequest.scrollForward ? step : -step))
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _scrollController!.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    final registry = widget.zoomRegistry;
    if (registry != null && registry.stepPage == _stepDisplayPage) {
      registry.stepPage = null;
    }
    _pageController?.dispose();
    _scrollController?.dispose();
    _webtoonZoom.dispose();
    super.dispose();
  }

  /// [page] is a SOURCE index (webtoon) — paged callers convert display
  /// indices first.
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
      final doubleTapZoom = ref.watch(readerWebtoonDoubleTapZoomProvider);
      final disableZoomOut = ref.watch(readerWebtoonDisableZoomOutProvider);
      Widget strip = NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (notif is ScrollEndNotification &&
              _scrollController != null &&
              widget.count > 0) {
            final pos = _scrollController!.position;
            // Index of the page crossing the viewport's vertical centre,
            // from the prefix sums of (estimated) item extents — tracks
            // real pages instead of the old scroll-ratio guess.
            final idx = _indexForOffset(
              pos.pixels + pos.viewportDimension / 2,
            );
            _report(idx);
            if (idx >= widget.count - 1) {
              widget.zoomRegistry?.onReachedLastSlot?.call();
            }
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.itemCount,
          // Read-ahead: build/decode pages well before they scroll on
          // screen (Mihon preloads 4 pages ahead; the Flutter default
          // ~250px meant every page boundary fetched on arrival and
          // stuttered).
          scrollCacheExtent: const ScrollCacheExtent.viewport(3),
          // Webtoon side padding: inset each page horizontally by a
          // fraction of the viewport width so strips don't run edge-to-
          // edge on wide screens. 0 = no inset (the default).
          padding: widget.sidePaddingFraction <= 0
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width *
                      widget.sidePaddingFraction,
                ),
          itemBuilder: (ctx, i) {
            if (i >= widget.count) return widget.transition!;
            // Reserve the page's real extent once its aspect is known so
            // later decodes don't shift content under the reader.
            return _WebtoonPageSlot(
              url: widget.pageUrlOf?.call(i),
              headers: widget.pageHeadersOf?.call(i),
              child: widget.itemBuilder(ctx, i),
            );
          },
        ),
      );
      // Webtoon zoom layer (Mihon WebtoonViewer): pinch zoom over the whole
      // strip; vertical drags keep scrolling the list (it wins the gesture
      // arena for them), horizontal pans move the zoomed strip. Double-tap
      // toggles 2x about the tap point — gated by its pref since the
      // double-tap recognizer delays single taps (chrome/nav), exactly the
      // trade Kotlin's pref exists for. "Disable zoom out" pins minScale.
      strip = InteractiveViewer(
        transformationController: _webtoonZoom,
        minScale: disableZoomOut ? 1 : 0.5,
        maxScale: 3,
        child: strip,
      );
      if (doubleTapZoom) {
        strip = GestureDetector(
          onDoubleTapDown: (d) => _webtoonDoubleTapDown = d,
          onDoubleTap: () {
            final d = _webtoonDoubleTapDown;
            if (d == null) return;
            if (_webtoonZoom.value.getMaxScaleOnAxis() > 1.01) {
              _webtoonZoom.value = Matrix4.identity();
              return;
            }
            const zoom = 2.0;
            final position = d.localPosition;
            _webtoonZoom.value = Matrix4.identity()
              ..translateByDouble(
                -position.dx * (zoom - 1),
                -position.dy * (zoom - 1),
                0,
                1,
              )
              ..scaleByDouble(zoom, zoom, zoom, 1);
          },
          child: strip,
        );
      }
      return strip;
    }
    final splitWide = ref.watch(readerDualPageSplitProvider);
    final invertSplit = ref.watch(readerDualPageInvertProvider);
    final mappingChanged = _rebuildSlots(splitWide: splitWide);
    if (mappingChanged && _pageController != null) {
      // The slot list shifted under the controller (a page just turned out
      // to be wide, or the pref flipped): re-anchor on the page — and the
      // same HALF of it — the reader was showing so nothing visibly jumps.
      final anchor = _currentSlot;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pageController == null) return;
        if (!_pageController!.hasClients) return;
        var target =
            _sourceToDisplay(_lastReported.clamp(0, widget.count));
        final slots = _slots;
        if (anchor != null && anchor.half != 0 && slots != null) {
          for (var d = 0; d < slots.length; d++) {
            if (slots[d].src == anchor.src && slots[d].half == anchor.half) {
              target = d;
              break;
            }
          }
        }
        _pageController!.jumpToPage(target);
      });
    }
    final displayTransitionIndex = _displayCount;
    return PageView.builder(
      controller: _pageController,
      scrollDirection:
          widget.mode.isHorizontal ? Axis.horizontal : Axis.vertical,
      reverse: widget.mode == ReadingMode.rightToLeft,
      itemCount: _displayCount + (widget.transition != null ? 1 : 0),
      onPageChanged: (d) {
        _currentSlot =
            (d < (_slots?.length ?? 0)) ? _slots![d] : (src: d, half: 0);
        _report(_displayToSource(d));
        if (_isLastRealSlot(d)) {
          widget.zoomRegistry?.onReachedLastSlot?.call();
        }
      },
      // Mount the adjacent page(s) one viewport ahead so their network
      // images start fetching/decoding before the user swipes to them,
      // instead of fetching on-demand at swipe time (the source of the
      // swipe lag). Mihon's HttpPageLoader preloads 4 ahead; this is the
      // idiomatic Flutter ±1 neighbour preload — deeper preloading would
      // need a custom cacheExtent tuned on-device.
      allowImplicitScrolling: true,
      itemBuilder: (ctx, d) {
        if (d >= displayTransitionIndex) return widget.transition!;
        final slot = _slots?[d] ?? (src: d, half: 0);
        final i = slot.src;
        if (slot.half != 0) {
          // Half of a split wide page (Mihon InsertPage). Reading order:
          // an L2R spread reads left half first, an R2L spread right half
          // first; invert swaps. Built directly from the backend provider
          // (crop/rotate decorators don't apply to halves — Kotlin splits
          // the raw bitmap too).
          final url = widget.pageUrlOf?.call(i);
          final firstIsLeft =
              (widget.mode != ReadingMode.rightToLeft) ^ invertSplit;
          final isFirst = slot.half == 1;
          final leftHalf = isFirst == firstIsLeft;
          return _ZoomablePage(
            url: url,
            headers: widget.pageHeadersOf?.call(i),
            mode: widget.mode,
            child: Center(
              child: url == null
                  ? widget.itemBuilder(ctx, i)
                  : Image(
                      image: HalfPageImageProvider(
                        SourceImage.providerFor(
                          url,
                          headers: widget.pageHeadersOf?.call(i),
                        ),
                        leftHalf: leftHalf,
                      ),
                      fit: widget.fit,
                      // Same loading/error affordances as whole pages —
                      // a failed half otherwise rendered a blank broken
                      // Image with no message.
                      frameBuilder: (ctx, child, frame, wasSync) {
                        if (frame != null || wasSync) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      },
                      errorBuilder: (ctx, error, _) => Center(
                        child: Text(
                          'Page ${i + 1} failed: $error',
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          );
        }
        return _ZoomablePage(
          url: widget.pageUrlOf?.call(i),
          headers: widget.pageHeadersOf?.call(i),
          mode: widget.mode,
          index: i,
          registry: widget.zoomRegistry,
          child: Center(child: widget.itemBuilder(ctx, i)),
        );
      },
    );
  }
}

/// Kotlin `ChapterTransition`: the info page between chapters — "Finished:
/// `current`" plus "Next: `next`" (or "There's no next chapter"). In paged
/// mode it occupies the slot after the last page; in continuous mode it's
/// the trailing list block. Tapping it jumps straight to the next chapter.
class _ChapterTransitionPage extends StatelessWidget {
  const _ChapterTransitionPage({
    required this.finishedTitle,
    required this.nextTitle,
    required this.textColor,
    required this.onNextChapter,
  });

  final String finishedTitle;

  /// Null = no next chapter.
  final String? nextTitle;
  final Color textColor;
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final dim = textColor.withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onNextChapter,
      // Bounded slots (PageView) take their own height; only the unbounded
      // webtoon list needs an explicit full-viewport block. MediaQuery
      // height inside an inset-shrunk PageView slot could overflow.
      child: LayoutBuilder(
        builder: (ctx, constraints) => SizedBox(
        height: constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(ctx).height,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Verbatim Mihon strings transition_finished /
                // transition_next / transition_no_next.
                Text('Finished:', style: TextStyle(color: dim, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  finishedTitle,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                if (nextTitle != null) ...[
                  Text('Next:', style: TextStyle(color: dim, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    nextTitle!,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else
                  Text(
                    "There's no next chapter",
                    style: TextStyle(color: dim, fontSize: 16),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Continuous-mode page slot: sizes itself with the page's decoded aspect
/// ratio (shared [_pageAspectCache]) so revisited pages occupy their final
/// extent before the bitmap arrives — kills the load-time layout shifts
/// that made long-strip scrolling jumpy. Falls back to intrinsic sizing
/// until the first decode. NOTE: extents assume the uncropped image; with
/// webtoon crop-borders on they may run slightly tall, which only pads the
/// scroll estimate.
class _WebtoonPageSlot extends StatefulWidget {
  const _WebtoonPageSlot({
    required this.url,
    this.headers,
    required this.child,
  });

  final String? url;

  /// Forwarded to the aspect probe — a header-less probe on a
  /// Referer-requiring source could 403 and poison the shared cache entry.
  final Map<String, String>? headers;
  final Widget child;

  @override
  State<_WebtoonPageSlot> createState() => _WebtoonPageSlotState();
}

class _WebtoonPageSlotState extends State<_WebtoonPageSlot> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _WebtoonPageSlot old) {
    super.didUpdateWidget(old);
    if (widget.url != old.url) {
      _aspect = widget.url == null ? null : _pageAspectCache[widget.url!];
      _resolve();
    }
  }

  void _resolve() {
    final url = widget.url;
    if (url == null) return;
    final cached = _pageAspectCache[url];
    if (cached != null) {
      _aspect = cached;
      return;
    }
    _resolvePageAspect(url, widget.headers, (aspect) {
      if (mounted && _aspect != aspect) setState(() => _aspect = aspect);
    });
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null) return widget.child;
    return AspectRatio(aspectRatio: aspect, child: widget.child);
  }
}

/// A single paged image wrapped in an [InteractiveViewer] with double-tap
/// to zoom. The zoom-in/out transition duration comes from
/// [readerDoubleTapAnimSpeedProvider]; a value of 0 applies the transform
/// instantly. Double-tapping while zoomed resets back to fit.
///
/// Wide (double-spread) pages additionally honour Mihon's "Zoom landscape
/// image" + "Zoom start position" prefs: when the decoded image is wider
/// than the viewport (and the scale type is fit-screen), the page starts
/// zoomed so its height fills the screen, positioned at the configured
/// edge (Automatic = the reading direction's leading edge).
class _ZoomablePage extends ConsumerStatefulWidget {
  const _ZoomablePage({
    required this.child,
    this.url,
    this.headers,
    required this.mode,
    this.index,
    this.registry,
  });

  final Widget child;
  final String? url;
  final Map<String, String>? headers;
  final ReadingMode mode;

  /// Source page index + the reader body's registry — registered so
  /// tap-navigation can ask this page to pan while zoomed (navigateToPan).
  final int? index;
  final _ZoomRegistry? registry;

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
  bool _initialZoomApplied = false;

  @override
  void initState() {
    super.initState();
    if (widget.index != null) {
      widget.registry?.register(widget.index!, this);
    }
    final url = widget.url;
    if (url == null) return;
    if (!ref.read(readerLandscapeZoomProvider)) return;
    if (ref.read(readerImageScaleTypeProvider) !=
        ReaderImageScaleType.fitScreen) {
      return;
    }
    _resolvePageAspect(url, widget.headers, (aspect) {
      if (!mounted || _initialZoomApplied) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeApplyInitialZoom(aspect);
      });
    });
  }

  /// Start wide pages zoomed to height-fill at the zoom-start edge. The
  /// child is laid out viewport-sized with the image contained (full width,
  /// vertically centred), so the matrix scales about the origin and shifts
  /// the chosen edge plus the centring band into view.
  void _maybeApplyInitialZoom(double imageAspect) {
    if (_initialZoomApplied) return;
    final size = context.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final viewportAspect = size.width / size.height;
    if (imageAspect <= viewportAspect) return; // not a wide page
    final scale = size.height * imageAspect / size.width;

    var start = ref.read(readerZoomStartProvider);
    if (start == ReaderZoomStart.automatic) {
      start = widget.mode == ReadingMode.rightToLeft
          ? ReaderZoomStart.right
          : ReaderZoomStart.left;
    }
    final overflowX = size.width * (scale - 1);
    final tx = switch (start) {
      ReaderZoomStart.right => -overflowX,
      ReaderZoomStart.center => -overflowX / 2,
      _ => 0.0, // left (and automatic→left)
    };
    // The contained image sits vertically centred: align its top edge.
    final ty = -scale * (size.height - size.width / imageAspect) / 2;
    _initialZoomApplied = true;
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  void didUpdateWidget(covariant _ZoomablePage old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index || old.registry != widget.registry) {
      if (old.index != null) old.registry?.unregister(old.index!, this);
      if (widget.index != null) widget.registry?.register(widget.index!, this);
    }
  }

  @override
  void dispose() {
    if (widget.index != null) {
      widget.registry?.unregister(widget.index!, this);
    }
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Mihon navigateToPan: while zoomed, a navigation step first pans one
  /// viewport step toward the reading direction; only from the edge does
  /// the caller turn the page. Returns false when not zoomed or already at
  /// the relevant edge.
  bool panTowards({required bool forward}) {
    final m = _controller.value;
    final scale = m.getMaxScaleOnAxis();
    if (scale <= 1.01) return false;
    final size = context.size;
    if (size == null) return false;
    final horizontal = widget.mode.isHorizontal;
    final extent = horizontal ? size.width : size.height;
    final maxOffset = extent * (scale - 1);
    if (maxOffset <= 1) return false;
    final t = m.getTranslation();
    final current = horizontal ? -t.x : -t.y; // 0..maxOffset from start edge
    // Forward in reading order pans toward increasing offset, except an
    // R2L pager where the content start is the right edge.
    final positive =
        !(horizontal && widget.mode == ReadingMode.rightToLeft);
    if (forward == positive ? current >= maxOffset - 1 : current <= 1) {
      return false;
    }
    final step = extent * 0.75;
    final next = (forward == positive ? current + step : current - step)
        .clamp(0.0, maxOffset);
    final target = m.clone();
    if (horizontal) {
      target.setTranslationRaw(-next, t.y, t.z);
    } else {
      target.setTranslationRaw(t.x, -next, t.z);
    }
    _applyMatrix(target);
    return true;
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
        // High enough that the landscape-zoom height-fill scale of a very
        // wide spread stays inside gesture bounds.
        maxScale: 8,
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

class _ReaderHeader extends ConsumerStatefulWidget {
  const _ReaderHeader({
    required this.manga,
    required this.chapter,
    this.chapterUrl,
  });

  final Manga manga;
  final Chapter chapter;

  /// Absolute chapter URL; non-null enables the WebView / browser / share
  /// overflow (Kotlin `ReaderTopBar`'s `takeIf { isHttpSource }` gating).
  final String? chapterUrl;

  @override
  ConsumerState<_ReaderHeader> createState() => _ReaderHeaderState();
}

class _ReaderHeaderState extends ConsumerState<_ReaderHeader> {
  // Optimistic bookmark state. Seeded from the loaded chapter (which is
  // resolved once per reader session) and flipped locally so the filled /
  // outline icon updates immediately, mirroring Kotlin's top-bar bookmark
  // toggle which reflects state without a full reload.
  late bool _bookmarked = widget.chapter.bookmark;

  @override
  void didUpdateWidget(covariant _ReaderHeader old) {
    super.didUpdateWidget(old);
    if (widget.chapter.id != old.chapter.id) {
      _bookmarked = widget.chapter.bookmark;
    }
  }

  Future<void> _toggleBookmark() async {
    final next = !_bookmarked;
    setState(() => _bookmarked = next);
    await ref
        .read(chapterRepositoryProvider)
        .setBookmark(widget.chapter.id, next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.manga.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface),
                ),
                Text(
                  widget.chapter.name.isEmpty
                      ? 'Chapter ${widget.chapter.chapterNumber}'
                      : widget.chapter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          // Bookmark toggle — Kotlin's primary reader top-bar action.
          IconButton(
            icon: Icon(
              _bookmarked ? Icons.bookmark : Icons.bookmark_border,
            ),
            tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark',
            onPressed: _toggleBookmark,
          ),
          // Kotlin ReaderTopBar overflow: WebView / browser / share, only
          // when the source yields an http(s) chapter URL.
          if (widget.chapterUrl != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                final url = widget.chapterUrl!;
                switch (value) {
                  case 'webview':
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => WebViewScreen(
                          url: url,
                          title: widget.manga.title,
                        ),
                      ),
                    );
                  case 'browser':
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  case 'share':
                    ReaderImageActions.shareText(url);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'webview',
                  child: Text('Open in WebView'),
                ),
                PopupMenuItem(
                  value: 'browser',
                  child: Text('Open in browser'),
                ),
                PopupMenuItem(value: 'share', child: Text('Share')),
              ],
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
