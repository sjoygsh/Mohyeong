import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';

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
                      itemBuilder: (_, i) => _ChapterTile(chapter: chapters[i]),
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

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter});

  final Chapter chapter;

  @override
  Widget build(BuildContext context) {
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
      // TODO(reader): push the reader route once it exists.
      onTap: () {},
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
