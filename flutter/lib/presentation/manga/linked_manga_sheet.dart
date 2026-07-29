import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_links_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../tide/tide.dart';

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
    return TideSheetPanel(
      child: StreamBuilder<List<Manga>>(
        stream: repo.watchLinked(primary.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 110,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: TideSpinner(size: 22, strokeWidth: 2),
                ),
              ),
            );
          }
          final linked = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Linked sources', style: TideText.display(21)),
                        const SizedBox(height: 6),
                        Text(
                          linked.isEmpty
                              ? 'Nothing linked yet'
                              : '${linked.length} linked',
                          style: TideText.caption(size: 13),
                        ),
                      ],
                    ),
                  ),
                  TideIconButton(
                    icon: Icons.add,
                    onTap: () => _addLink(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (linked.isEmpty)
                Text(
                  'Attach another title from your library and its new '
                  'chapters will appear under this one.',
                  style: TideText.body(),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: linked.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LinkedRow(
                      primaryId: primary.id,
                      linked: linked[i],
                      repo: repo,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TideButton(
                label: 'Done',
                primary: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addLink(BuildContext context, WidgetRef ref) async {
    final picked = await showTideSheet<Manga>(
      context,
      (_) => _PickFavoriteSheet(excludeId: primary.id),
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
    return TideGlass(
      radius: TideRadius.row,
      tintTop: 0.085,
      tintBottom: 0.03,
      highlight: 0.15,
      border: 0.10,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TideRadius.tag),
            child: SizedBox(
              width: 38,
              height: 52,
              // TideCover, not a bare image: it resolves the per-source
              // request headers, which several sources need to serve art.
              child: TideCover(manga: linked, cacheWidth: 240),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  linked.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(size: 14),
                ),
                const SizedBox(height: 3),
                Text('Source ${linked.source}',
                    style: TideText.caption(size: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TideIconButton(
            icon: Icons.link_off,
            onTap: () => repo.unlink(primaryId, linked.id),
          ),
        ],
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
    return TideSheetPanel(
      child: StreamBuilder<List<Manga>>(
        stream: mangaRepo.watchFavorites(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 110,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: TideSpinner(size: 22, strokeWidth: 2),
                ),
              ),
            );
          }
          final candidates = snap.data!
              .where((m) => m.id != excludeId)
              .toList(growable: false);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Link a title', style: TideText.display(21)),
              const SizedBox(height: 18),
              if (candidates.isEmpty)
                Text(
                  'There is nothing else in your library yet. Add another '
                  'title first and it can be linked here.',
                  style: TideText.body(),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = candidates[i];
                      return TideGlass(
                        radius: TideRadius.row,
                        tintTop: 0.085,
                        tintBottom: 0.03,
                        highlight: 0.15,
                        border: 0.10,
                        onTap: () => Navigator.of(context).pop(m),
                        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(TideRadius.tag),
                              child: SizedBox(
                                width: 34,
                                height: 46,
                                child: TideCover(manga: m, cacheWidth: 200),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    m.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TideText.title(size: 14),
                                  ),
                                  const SizedBox(height: 3),
                                  Text('Source ${m.source}',
                                      style: TideText.caption(size: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              TideButton(
                label: 'Cancel',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ),
    );
  }
}
