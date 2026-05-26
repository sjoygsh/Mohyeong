import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';

/// Reader screen scaffold.
///
/// The reader UI is intentionally a shell at this stage: page fetching depends
/// on the source/extension architecture which lands in v1.1+. Until then the
/// screen loads the chapter metadata, exposes the next/previous chapter
/// controls, and stamps the chapter as read when the user explicitly marks it
/// done. Once a page-fetch pipeline exists, the placeholder body is replaced
/// with the actual PageView of decoded images.
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

  @override
  Widget build(BuildContext context) {
    final chapterRepo = ref.watch(chapterRepositoryProvider);
    final mangaRepo = ref.watch(mangaRepositoryProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<_ReaderData?>(
        future: _loadReaderData(
          chapterRepo,
          mangaRepo,
          widget.mangaId,
          _chapterId,
        ),
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
            onJumpToChapter: (id) => setState(() => _chapterId = id),
            onMarkRead: () async {
              await chapterRepo.setRead(data.chapter.id, true);
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
  return _ReaderData(chapter: target, manga: manga, siblings: siblings);
}

class _ReaderData {
  const _ReaderData({
    required this.chapter,
    required this.manga,
    required this.siblings,
  });

  final Chapter chapter;
  final Manga manga;
  final List<Chapter> siblings;

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
          const Expanded(child: _PendingPipelineNotice()),
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

class _PendingPipelineNotice extends StatelessWidget {
  const _PendingPipelineNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                color: Colors.white54, size: 64),
            SizedBox(height: 12),
            Text(
              'Page fetching is not implemented yet.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'The reader UI is in place; pages will appear once the '
              'source/extension pipeline lands.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
