import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_links_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';

/// Modal sheet for managing the cluster of "linked" alternate sources
/// attached to a manga (different translations / mirror sources). The
/// row the sheet is opened from is always treated as the *primary*; the
/// linked list is everything else in the cluster.
///
/// "Add" picks from the user's favourites; we deliberately don't surface
/// cross-source search here because v1.0 doesn't have the source-side
/// catalog wired up for that flow.
class LinkedMangaSheet extends ConsumerWidget {
  const LinkedMangaSheet({super.key, required this.primary});

  final Manga primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mangaLinksRepositoryProvider);
    return SafeArea(
      child: StreamBuilder<List<Manga>>(
        stream: repo.watchLinked(primary.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final linked = snap.data!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Linked sources',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      onPressed: () => _addLink(context, ref),
                    ),
                  ],
                ),
              ),
              if (linked.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Text(
                    'No linked sources yet. Use Add to attach another '
                    'manga from your library — chapter updates on it will '
                    'show under this title in the Updates tab.',
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: linked.length,
                    itemBuilder: (_, i) => _LinkedRow(
                      primaryId: primary.id,
                      linked: linked[i],
                      repo: repo,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addLink(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<Manga>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickFavoriteSheet(excludeId: primary.id),
    );
    if (picked == null) return;
    await ref.read(mangaLinksRepositoryProvider).link(primary.id, picked.id);
  }
}

class _LinkedRow extends StatelessWidget {
  const _LinkedRow({
    required this.primaryId,
    required this.linked,
    required this.repo,
  });

  final int primaryId;
  final Manga linked;
  final MangaLinksRepository repo;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: linked.thumbnailUrl == null || linked.thumbnailUrl!.isEmpty
              ? Container(color: placeholderColor)
              : SourceImage(
                  url: linked.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_) => Container(color: placeholderColor),
                  errorWidget: (_, _) => Container(color: placeholderColor),
                ),
        ),
      ),
      title: Text(
        linked.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('Source ${linked.source}'),
      trailing: IconButton(
        icon: const Icon(Icons.link_off),
        tooltip: 'Unlink',
        onPressed: () => repo.unlink(primaryId, linked.id),
      ),
    );
  }
}

class _PickFavoriteSheet extends ConsumerWidget {
  const _PickFavoriteSheet({required this.excludeId});

  final int excludeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaRepo = ref.watch(mangaRepositoryProvider);
    return SafeArea(
      child: StreamBuilder<List<Manga>>(
        stream: mangaRepo.watchFavorites(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final candidates = snap.data!
              .where((m) => m.id != excludeId)
              .toList(growable: false);
          if (candidates.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No other manga in your library. Favourite at least one '
                'more title to link it here.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Pick a manga to link',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final m = candidates[i];
                    return ListTile(
                      title: Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('Source ${m.source}'),
                      onTap: () => Navigator.of(context).pop(m),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
