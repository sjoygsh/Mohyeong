import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/category/model/category.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../reader/reader_screen.dart';

/// Manga details: cover + metadata header followed by the chapter list.
/// Tapping a chapter is a no-op until the reader screen ships.
class MangaDetailsScreen extends ConsumerWidget {
  const MangaDetailsScreen({super.key, required this.mangaId});

  final int mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaRepo = ref.watch(mangaRepositoryProvider);
    final chapterRepo = ref.watch(chapterRepositoryProvider);

    return Scaffold(
      body: StreamBuilder<Manga?>(
        stream: mangaRepo.watchById(mangaId),
        builder: (context, mangaSnap) {
          if (mangaSnap.hasError) {
            return _Error(error: mangaSnap.error!);
          }
          if (!mangaSnap.hasData) {
            return const _LoadingScaffold();
          }
          final manga = mangaSnap.data;
          if (manga == null) {
            return const _MissingManga();
          }
          return StreamBuilder<List<Chapter>>(
            stream: chapterRepo.watchByMangaId(mangaId),
            builder: (context, chapSnap) {
              final chapters = chapSnap.data ?? const <Chapter>[];
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 280,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(
                        manga.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      background: _HeaderBackdrop(manga: manga),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          manga.favorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        tooltip: manga.favorite
                            ? 'Remove from library'
                            : 'Add to library',
                        onPressed: () => _toggleFavorite(context, ref, manga),
                      ),
                      if (manga.favorite)
                        IconButton(
                          icon: const Icon(Icons.label_outline),
                          tooltip: 'Edit categories',
                          onPressed: () =>
                              _editCategories(context, ref, manga),
                        ),
                    ],
                  ),
                  SliverToBoxAdapter(child: _Metadata(manga: manga)),
                  SliverToBoxAdapter(
                    child: _ChapterListHeader(count: chapters.length),
                  ),
                  if (chapSnap.hasError)
                    SliverToBoxAdapter(child: _Error(error: chapSnap.error!))
                  else if (!chapSnap.hasData)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (chapters.isEmpty)
                    const SliverToBoxAdapter(child: _NoChapters())
                  else
                    SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (_, i) => _ChapterTile(
                        manga: manga,
                        chapter: chapters[i],
                        chapterRepo: chapterRepo,
                        downloadRepo: ref.watch(downloadRepositoryProvider),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _toggleFavorite(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final mangaRepo = ref.read(mangaRepositoryProvider);
  if (manga.favorite) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: const Text(
          'The manga stays in the database (so your read history is kept) '
          'but disappears from the Library tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
  }
  await mangaRepo.setFavorite(manga.id, !manga.favorite);
  // When removing from library, also clear category memberships so the
  // manga doesn't reappear in a category-filtered view if it's added back.
  if (manga.favorite) {
    final categoryRepo = ref.read(categoryRepositoryProvider);
    await categoryRepo.setCategoriesForManga(manga.id, const <int>{});
  }
}

Future<void> _editCategories(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final categoryRepo = ref.read(categoryRepositoryProvider);
  final all = await categoryRepo.getAll();
  final userCategories =
      all.where((c) => !c.isSystemCategory).toList(growable: false);
  if (!context.mounted) return;
  if (userCategories.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No categories yet. Create one in More -> Categories first.',
        ),
      ),
    );
    return;
  }
  final initial = await categoryRepo.getCategoryIdsForManga(manga.id);
  if (!context.mounted) return;
  final selection = await showModalBottomSheet<Set<int>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CategorySelector(
      categories: userCategories,
      initiallySelected: initial,
    ),
  );
  if (selection != null) {
    await categoryRepo.setCategoriesForManga(manga.id, selection);
  }
}

class _CategorySelector extends StatefulWidget {
  const _CategorySelector({
    required this.categories,
    required this.initiallySelected,
  });

  final List<Category> categories;
  final Set<int> initiallySelected;

  @override
  State<_CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<_CategorySelector> {
  late final Set<int> _selected = {...widget.initiallySelected};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.categories.map((c) {
                  final checked = _selected.contains(c.id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(c.id);
                        } else {
                          _selected.remove(c.id);
                        }
                      });
                    },
                    title: Text(c.name),
                  );
                }).toList(growable: false),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBackdrop extends StatelessWidget {
  const _HeaderBackdrop({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    final image = (url == null || url.isEmpty)
        ? Container(color: placeholderColor)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: placeholderColor),
            errorWidget: (_, _, _) => Container(color: placeholderColor),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        // Dim gradient so the title stays legible on light covers.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final author = manga.author?.trim();
    final artist = manga.artist?.trim();
    final showArtist =
        artist != null && artist.isNotEmpty && artist != author;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (author != null && author.isNotEmpty)
            Text(author, style: Theme.of(context).textTheme.titleSmall),
          if (showArtist)
            Text(
              artist,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Text(_statusLabel(manga.status),
              style: Theme.of(context).textTheme.bodyMedium),
          if (manga.description != null && manga.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              manga.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (manga.genre != null && manga.genre!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: manga.genre!
                  .map((g) => Chip(label: Text(g)))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  // Mirrors SManga.STATUS_*: 0=Unknown, 1=Ongoing, 2=Completed, 3=Licensed,
  // 4=Publishing Finished, 5=Cancelled, 6=On Hiatus.
  String _statusLabel(int status) {
    switch (status) {
      case 1:
        return 'Ongoing';
      case 2:
        return 'Completed';
      case 3:
        return 'Licensed';
      case 4:
        return 'Publishing finished';
      case 5:
        return 'Cancelled';
      case 6:
        return 'On hiatus';
      default:
        return 'Unknown status';
    }
  }
}

class _ChapterListHeader extends StatelessWidget {
  const _ChapterListHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        '$count chapters',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ChapterTile extends StatefulWidget {
  const _ChapterTile({
    required this.manga,
    required this.chapter,
    required this.chapterRepo,
    required this.downloadRepo,
  });

  final Manga manga;
  final Chapter chapter;
  final ChapterRepository chapterRepo;
  final DownloadRepository downloadRepo;

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  late DownloadState _downloadState = DownloadState.deleted;
  double? _progress;
  StreamSubscription<DownloadEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _refreshDownloaded();
    _sub = widget.downloadRepo.events.listen((e) {
      if (e.chapterId != widget.chapter.id) return;
      if (!mounted) return;
      setState(() {
        _downloadState = e.state;
        _progress = e.progress;
      });
    });
  }

  Future<void> _refreshDownloaded() async {
    final done = await widget.downloadRepo.isDownloaded(
      widget.manga.source,
      widget.manga.id,
      widget.chapter.id,
    );
    if (!mounted) return;
    setState(() {
      _downloadState = done ? DownloadState.completed : DownloadState.deleted;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final title = chapter.name.isEmpty
        ? 'Chapter ${_formatChapterNumber(chapter.chapterNumber)}'
        : chapter.name;
    final scanlator = chapter.scanlator;
    final subtitleParts = <String>[];
    if (chapter.dateUpload > 0) {
      subtitleParts.add(_formatDate(chapter.dateUpload));
    }
    if (scanlator != null && scanlator.isNotEmpty) {
      subtitleParts.add(scanlator);
    }
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: chapter.read
              ? Theme.of(context).disabledColor
              : Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
      leading: chapter.bookmark
          ? const Icon(Icons.bookmark, size: 20)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DownloadIndicator(state: _downloadState, progress: _progress),
          PopupMenuButton<_ChapterAction>(
            onSelected: (action) {
              final chapterRepo = widget.chapterRepo;
              switch (action) {
                case _ChapterAction.markRead:
                  chapterRepo.setRead(chapter.id, true);
                case _ChapterAction.markUnread:
                  chapterRepo.setRead(chapter.id, false);
                case _ChapterAction.bookmark:
                  chapterRepo.setBookmark(chapter.id, true);
                case _ChapterAction.unbookmark:
                  chapterRepo.setBookmark(chapter.id, false);
                case _ChapterAction.download:
                  widget.downloadRepo.enqueue(widget.manga, chapter);
                case _ChapterAction.deleteDownload:
                  widget.downloadRepo.deleteDownload(
                    widget.manga.source,
                    widget.manga.id,
                    chapter.id,
                  );
              }
            },
            itemBuilder: (_) => [
              if (!chapter.read)
                const PopupMenuItem(
                  value: _ChapterAction.markRead,
                  child: Text('Mark as read'),
                ),
              if (chapter.read)
                const PopupMenuItem(
                  value: _ChapterAction.markUnread,
                  child: Text('Mark as unread'),
                ),
              if (!chapter.bookmark)
                const PopupMenuItem(
                  value: _ChapterAction.bookmark,
                  child: Text('Bookmark'),
                ),
              if (chapter.bookmark)
                const PopupMenuItem(
                  value: _ChapterAction.unbookmark,
                  child: Text('Remove bookmark'),
                ),
              if (_downloadState != DownloadState.completed &&
                  _downloadState != DownloadState.downloading &&
                  _downloadState != DownloadState.queued)
                const PopupMenuItem(
                  value: _ChapterAction.download,
                  child: Text('Download'),
                ),
              if (_downloadState == DownloadState.completed)
                const PopupMenuItem(
                  value: _ChapterAction.deleteDownload,
                  child: Text('Delete download'),
                ),
            ],
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              mangaId: chapter.mangaId,
              chapterId: chapter.id,
            ),
          ),
        );
      },
    );
  }

  String _formatChapterNumber(double n) {
    if (n < 0) return '?';
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toString();
  }

  String _formatDate(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

enum _ChapterAction {
  markRead,
  markUnread,
  bookmark,
  unbookmark,
  download,
  deleteDownload,
}

class _DownloadIndicator extends StatelessWidget {
  const _DownloadIndicator({required this.state, required this.progress});

  final DownloadState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case DownloadState.queued:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.hourglass_empty, size: 18),
        );
      case DownloadState.downloading:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
            ),
          ),
        );
      case DownloadState.completed:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.download_done, size: 18),
        );
      case DownloadState.failed:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(Icons.error_outline, size: 18, color: Colors.redAccent),
        );
      case DownloadState.deleted:
        return const SizedBox.shrink();
    }
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _MissingManga extends StatelessWidget {
  const _MissingManga();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(child: Text('Manga not found.')),
    );
  }
}

class _NoChapters extends StatelessWidget {
  const _NoChapters();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: Text('No chapters yet.')),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: Text('Error: $error')),
    );
  }
}
