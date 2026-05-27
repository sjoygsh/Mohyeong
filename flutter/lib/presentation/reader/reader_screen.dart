import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/track/track_updater.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_chapter.dart';

/// Reader screen — fetches the chapter's page list from the manga's source
/// and displays them in a vertical scroll view.
///
/// Three failure modes are surfaced explicitly:
///   * Manga or chapter missing in DB → "Chapter not found".
///   * Source not installed → tell the user which source they need.
///   * Page fetch fails → show error + retry.
///
/// Mihon ships three reader modes (vertical/webtoon, paged LTR, paged RTL).
/// v1.0 defaults to vertical scroll; per-manga viewer flags will route to
/// the right widget once the paged renderer lands.
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
          return _ReaderBody(
            data: data,
            onJumpToChapter: _jumpToChapter,
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
    required this.onJumpToChapter,
    required this.onMarkRead,
  });

  final _ReaderData data;
  final ValueChanged<int> onJumpToChapter;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final prev = data.previousChapter;
    final next = data.nextChapter;
    return SafeArea(
      child: Column(
        children: [
          _ReaderHeader(manga: data.manga, chapter: data.chapter),
          Expanded(
            child: data.localPagePaths != null
                ? _LocalPageList(paths: data.localPagePaths!)
                : data.source == null
                    ? _SourceUnavailable(
                        mangaSourceId: data.manga.source,
                        error: data.sourceError,
                      )
                    : _PageList(
                        source: data.source!,
                        chapter: data.chapter,
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

class _PageList extends StatefulWidget {
  const _PageList({required this.source, required this.chapter});

  final MangaSource source;
  final Chapter chapter;

  @override
  State<_PageList> createState() => _PageListState();
}

class _PageListState extends State<_PageList> {
  Future<List<SourcePage>>? _pages;

  @override
  void initState() {
    super.initState();
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
                      setState(() {
                        _pages = widget.source.fetchPageList(
                          SourceChapter(
                            url: widget.chapter.url,
                            name: widget.chapter.name,
                          ),
                        );
                      });
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
        return ListView.builder(
          itemCount: pages.length,
          itemBuilder: (_, i) {
            final page = pages[i];
            final imageUrl = page.imageUrl ?? page.url;
            return CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.fitWidth,
              httpHeaders: page.headers,
              placeholder: (_, _) => const SizedBox(
                height: 400,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
              errorWidget: (_, _, error) => SizedBox(
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
  const _LocalPageList({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const Center(
        child: Text('No pages.', style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      itemCount: paths.length,
      itemBuilder: (_, i) => Image.file(
        File(paths[i]),
        fit: BoxFit.fitWidth,
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
  const _ReaderHeader({required this.manga, required this.chapter});

  final Manga manga;
  final Chapter chapter;

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
