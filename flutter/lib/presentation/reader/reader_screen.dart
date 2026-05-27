import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/reader/reader_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/track/track_updater.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
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

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late int _chapterId = widget.chapterId;
  Future<_ReaderData?>? _data;

  @override
  void initState() {
    super.initState();
    _reload();
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_ReaderData?>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ReaderError(error: snap.error!);
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
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

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.data,
    required this.mode,
    required this.onJumpToChapter,
    required this.onChangeMode,
    required this.onPageChanged,
    required this.onMarkRead,
  });

  final _ReaderData data;
  final ReadingMode mode;
  final ValueChanged<int> onJumpToChapter;
  final ValueChanged<ReadingMode> onChangeMode;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final prev = data.previousChapter;
    final next = data.nextChapter;
    return SafeArea(
      child: Column(
        children: [
          _ReaderHeader(
            manga: data.manga,
            chapter: data.chapter,
            mode: mode,
            onChangeMode: onChangeMode,
          ),
          Expanded(
            child: _ReaderViewport(
              data: data,
              mode: mode,
              onPageChanged: onPageChanged,
            ),
          ),
          _ReaderControls(
            onPrev: prev == null ? null : () => onJumpToChapter(prev.id),
            onNext: next == null ? null : () => onJumpToChapter(next.id),
            onMarkRead: onMarkRead,
            alreadyRead: data.chapter.read,
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
    required this.onPageChanged,
  });

  final _ReaderData data;
  final ReadingMode mode;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (data.localPagePaths != null) {
      return _LocalPageList(
        paths: data.localPagePaths!,
        mode: mode,
        initialPage: data.chapter.lastPageRead,
        onPageChanged: onPageChanged,
      );
    }
    if (data.source == null) {
      return _SourceUnavailable(
        mangaSourceId: data.manga.source,
        error: data.sourceError,
      );
    }
    return _PageList(
      source: data.source!,
      chapter: data.chapter,
      mode: mode,
      onPageChanged: onPageChanged,
    );
  }
}

class _PageList extends StatefulWidget {
  const _PageList({
    required this.source,
    required this.chapter,
    required this.mode,
    required this.onPageChanged,
  });

  final MangaSource source;
  final Chapter chapter;
  final ReadingMode mode;
  final ValueChanged<int> onPageChanged;

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
        if (pages.isEmpty) {
          return const Center(
            child: Text('No pages.', style: TextStyle(color: Colors.white70)),
          );
        }
        return _PagesView(
          count: pages.length,
          mode: widget.mode,
          initialPage: widget.chapter.lastPageRead,
          onPageChanged: widget.onPageChanged,
          itemBuilder: (_, i) {
            final page = pages[i];
            final imageUrl = page.imageUrl ?? page.url;
            return SourceImage(
              url: imageUrl,
              fit: BoxFit.contain,
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
    required this.initialPage,
    required this.onPageChanged,
  });

  final List<String> paths;
  final ReadingMode mode;
  final int initialPage;
  final ValueChanged<int> onPageChanged;

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
      initialPage: initialPage,
      onPageChanged: onPageChanged,
      itemBuilder: (_, i) => Image.file(
        File(paths[i]),
        fit: BoxFit.contain,
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
    required this.initialPage,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  final int count;
  final ReadingMode mode;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
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
      itemBuilder: (ctx, i) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(child: widget.itemBuilder(ctx, i)),
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
