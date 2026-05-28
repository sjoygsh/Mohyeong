import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/download/download_repository.dart';
import '../../data/manga/excluded_scanlators_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/source_repository.dart';
import '../../data/track/track_updater.dart';
import '../../domain/category/model/category.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../../domain/source/model/source.dart';
import '../common/source_image.dart';
import '../reader/reader_screen.dart';
import '../track/manga_tracking_sheet.dart';
import 'chapter_settings_sheet.dart';
import 'linked_manga_sheet.dart';
import 'scanlator_filter_sheet.dart';

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
              final nextUnread = _pickNextUnread(chapters);
              return Scaffold(
                floatingActionButton: nextUnread == null
                    ? null
                    : _ContinueReadingFab(
                        manga: manga,
                        chapter: nextUnread,
                        anyRead: chapters.any((c) => c.read),
                      ),
                body: CustomScrollView(
                  slivers: [
                  SliverAppBar(
                    pinned: true,
                    title: Text(
                      manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    actions: [
                      if (manga.favorite)
                        IconButton(
                          icon: const Icon(Icons.label_outline),
                          tooltip: 'Edit categories',
                          onPressed: () =>
                              _editCategories(context, ref, manga),
                        ),
                      if (manga.favorite)
                        IconButton(
                          icon: const Icon(Icons.link),
                          tooltip: 'Linked sources',
                          onPressed: () => _openLinkedSheet(context, manga),
                        ),
                    ],
                  ),
                  SliverToBoxAdapter(child: _MangaInfoBox(manga: manga)),
                  SliverToBoxAdapter(
                    child: _MangaActionRow(
                      manga: manga,
                      onAddToLibrary: () => _toggleFavorite(context, ref, manga),
                      onTracking: () => _openTrackingSheet(context, manga),
                      onOpenInBrowser: () => _openInBrowser(context, ref, manga),
                    ),
                  ),
                  SliverToBoxAdapter(child: _DescriptionAndTags(manga: manga)),
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
                    ...const [
                      SliverToBoxAdapter(
                        child: _ChapterListHeader(
                          visibleCount: 0,
                          totalCount: 0,
                          mangaForSheet: null,
                        ),
                      ),
                      SliverToBoxAdapter(child: _NoChapters()),
                    ]
                  else
                    SliverToBoxAdapter(
                      child: _ChaptersSection(
                        manga: manga,
                        chapters: chapters,
                        chapterRepo: chapterRepo,
                      ),
                    ),
                ],
              ),
            );
            },
          );
        },
      ),
    );
  }
}

/// Renders the chapter list header + the filter/sort-applied chapter
/// tiles. Watches the manga's excluded-scanlator set so toggling
/// exclusions live-updates the list.
///
/// The filter/sort logic mirrors Mihon's `GetChaptersByMangaId` +
/// `applyFilters` pipeline: drop excluded-scanlator rows, apply the
/// tri-state unread/bookmarked filters, then sort by the configured key
/// in the configured direction. Chapter display mode (name vs number)
/// is applied at the tile level.
class _ChaptersSection extends ConsumerWidget {
  const _ChaptersSection({
    required this.manga,
    required this.chapters,
    required this.chapterRepo,
  });

  final Manga manga;
  final List<Chapter> chapters;
  final ChapterRepository chapterRepo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excludedRepo = ref.watch(excludedScanlatorsRepositoryProvider);
    final downloadRepo = ref.watch(downloadRepositoryProvider);
    return StreamBuilder<Set<String>>(
      stream: excludedRepo.watchByMangaId(manga.id),
      builder: (context, excludedSnap) {
        final excluded = excludedSnap.data ?? const <String>{};
        // Only probe the filesystem when the user has actually engaged
        // the downloaded filter axis. Common path stays sync.
        if (manga.downloadedFilter == TriState.disabled) {
          return _buildBody(context, excluded, null, downloadRepo);
        }
        return FutureBuilder<Set<int>>(
          future: downloadRepo.listDownloadedChapterIds(manga.source, manga.id),
          builder: (context, downloadedSnap) {
            return _buildBody(
              context,
              excluded,
              downloadedSnap.data ?? const <int>{},
              downloadRepo,
            );
          },
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    Set<String> excluded,
    Set<int>? downloadedIds,
    DownloadRepository downloadRepo,
  ) {
    final availableScanlators = <String>{
      for (final c in chapters)
        if (c.scanlator != null && c.scanlator!.isNotEmpty) c.scanlator!,
    };

    final filtered = chapters.where((c) {
      if (excluded.contains(c.scanlator)) return false;
      final unreadOk = applyTriState(manga.unreadFilter, () => !c.read);
      final bookmarkedOk =
          applyTriState(manga.bookmarkedFilter, () => c.bookmark);
      final downloadedOk = downloadedIds == null
          ? true
          : applyTriState(
              manga.downloadedFilter,
              () => downloadedIds.contains(c.id),
            );
      return unreadOk && bookmarkedOk && downloadedOk;
    }).toList(growable: false);

    final sorted = [...filtered]..sort((a, b) {
      int cmp;
      switch (manga.sorting) {
        case Manga.chapterSortingNumber:
          cmp = a.chapterNumber.compareTo(b.chapterNumber);
        case Manga.chapterSortingUploadDate:
          cmp = a.dateUpload.compareTo(b.dateUpload);
        case Manga.chapterSortingAlphabet:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default:
          cmp = a.sourceOrder.compareTo(b.sourceOrder);
      }
      return manga.sortDescending() ? -cmp : cmp;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChapterListHeader(
          visibleCount: sorted.length,
          totalCount: chapters.length,
          mangaForSheet: manga,
          availableScanlators: availableScanlators,
          excludedScanlators: excluded,
        ),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('No chapters match the current filter.'),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sorted.length,
            itemBuilder: (_, i) => _ChapterTile(
              manga: manga,
              chapter: sorted[i],
              chapterRepo: chapterRepo,
              downloadRepo: downloadRepo,
            ),
          ),
      ],
    );
  }
}

/// Returns the next chapter the user should read, or null if every
/// chapter is already marked read (or the list is empty).
///
/// Mirrors Mihon's `getNextChapter` behaviour: order chapters by their
/// source-supplied order, then pick the lowest one that hasn't been
/// read yet. Excluded scanlators are NOT filtered here — Mihon shows
/// the FAB even when filters hide chapters, and we want the same.
Chapter? _pickNextUnread(List<Chapter> chapters) {
  final unread = chapters.where((c) => !c.read).toList(growable: false);
  if (unread.isEmpty) return null;
  unread.sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
  return unread.first;
}

/// Floating action button that jumps straight into the next unread
/// chapter. Label flips between "Start" (no chapters read yet) and
/// "Continue" (at least one chapter is already read) — same wording as
/// Mihon's manga details screen.
class _ContinueReadingFab extends StatelessWidget {
  const _ContinueReadingFab({
    required this.manga,
    required this.chapter,
    required this.anyRead,
  });

  final Manga manga;
  final Chapter chapter;
  final bool anyRead;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      icon: const Icon(Icons.play_arrow),
      label: Text(anyRead ? 'Continue' : 'Start'),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              mangaId: manga.id,
              chapterId: chapter.id,
            ),
          ),
        );
      },
    );
  }
}

void _openChapterSettingsSheet(BuildContext context, Manga manga) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChapterSettingsSheet(manga: manga),
  );
}

void _openScanlatorFilterSheet(
  BuildContext context, {
  required int mangaId,
  required Set<String> available,
  required Set<String> excluded,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ScanlatorFilterSheet(
      mangaId: mangaId,
      availableScanlators: available,
      initiallyExcluded: excluded,
    ),
  );
}

void _openTrackingSheet(BuildContext context, Manga manga) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MangaTrackingSheet(manga: manga),
  );
}

void _openLinkedSheet(BuildContext context, Manga manga) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LinkedMangaSheet(primary: manga),
  );
}

/// Mirrors Mihon's `MangaScreenModel.openMangaInWebView`: resolve the
/// source's `baseUrl`, join it with the relative `manga.url`, and hand
/// the result off to the platform browser via url_launcher. Falls back
/// to the raw `manga.url` if the source can't be looked up (the source
/// may be uninstalled — the URL is sometimes absolute anyway).
Future<void> _openInBrowser(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final messenger = ScaffoldMessenger.of(context);
  String full = manga.url;
  if (!full.startsWith('http')) {
    try {
      final source =
          await ref.read(extensionRepositoryProvider).getSource('${manga.source}');
      final base = source.baseUrl;
      if (base.isNotEmpty) {
        full =
            '${base.replaceAll(RegExp(r'/+$'), '')}/${manga.url.replaceAll(RegExp(r'^/+'), '')}';
      }
    } catch (_) {
      // Source not installed — fall through with the raw relative URL.
    }
  }
  final uri = Uri.tryParse(full);
  if (uri == null || !uri.hasScheme) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No URL available for this entry')),
    );
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open $uri')),
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

/// Mihon-style info header: blurred backdrop of the cover behind a row
/// containing the cover thumbnail and the title / author / artist /
/// status / source name. Tablet-width handling is punted — Mihon's
/// `MangaAndSourceTitlesLarge` centers the cover above the metadata at
/// ≥720dp, but the phone-first small variant is what we render here.
class _MangaInfoBox extends ConsumerWidget {
  const _MangaInfoBox({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceRepo = ref.watch(sourceRepositoryProvider);
    return Stack(
      children: [
        // Blurred backdrop. Mihon uses the cover image with a 4dp blur
        // and 0.2 alpha plus a transparent → background-colour gradient
        // so the foreground row stays legible on light covers.
        Positioned.fill(child: _Backdrop(manga: manga)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 110,
                  height: 155, // ~book aspect ratio 1:1.41
                  child: _CoverImage(url: manga.thumbnailUrl),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _IconText(
                      icon: Icons.person_outline,
                      text: manga.author?.trim().isNotEmpty == true
                          ? manga.author!.trim()
                          : 'Unknown author',
                    ),
                    if (manga.artist?.trim().isNotEmpty == true &&
                        manga.artist!.trim() != manga.author?.trim()) ...[
                      const SizedBox(height: 2),
                      _IconText(
                        icon: Icons.brush_outlined,
                        text: manga.artist!.trim(),
                      ),
                    ],
                    const SizedBox(height: 6),
                    FutureBuilder<Source?>(
                      future: sourceRepo.findById(manga.source),
                      builder: (context, snap) {
                        final src = snap.data;
                        return _StatusRow(status: manga.status, source: src);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final url = manga.thumbnailUrl;
    final bg = Theme.of(context).colorScheme.surface;
    if (url == null || url.isEmpty) {
      return Container(color: bg);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.25,
          child: SourceImage(
            url: url,
            fit: BoxFit.cover,
            placeholder: (_) => Container(color: bg),
            errorWidget: (_, _) => Container(color: bg),
          ),
        ),
        // Blur over the dimmed cover.
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const SizedBox.shrink(),
        ),
        // Transparent → background gradient for legibility.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, bg],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    if (url == null || url!.isEmpty) {
      return Container(color: placeholder);
    }
    return SourceImage(
      url: url!,
      fit: BoxFit.cover,
      placeholder: (_) => Container(color: placeholder),
      errorWidget: (_, _) => Container(color: placeholder),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Status icon + label · source name. Source name renders only when the
/// source lookup resolves; otherwise the row degrades to status alone.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.source});

  final int status;
  final Source? source;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Row(
      children: [
        Icon(_statusIcon(status), size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _statusLabel(status),
            style: style,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (source != null) ...[
          Text(' • ', style: style),
          if (source!.isStub)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          Flexible(
            child: Text(
              source!.visualName,
              style: style,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );
  }
}

/// 3-button action row right under the info box: Add-to-library / Track
/// / Open-in-browser. Mirrors Mihon's `MangaActionRow`. The interval
/// button is skipped — it needs the auto-update scheduler hooked up
/// per-manga, which isn't in v1.0 scope.
class _MangaActionRow extends StatelessWidget {
  const _MangaActionRow({
    required this.manga,
    required this.onAddToLibrary,
    required this.onTracking,
    required this.onOpenInBrowser,
  });

  final Manga manga;
  final VoidCallback onAddToLibrary;
  final VoidCallback onTracking;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: manga.favorite ? Icons.favorite : Icons.favorite_border,
              label: manga.favorite ? 'In library' : 'Add to library',
              color: manga.favorite ? primary : muted,
              onPressed: onAddToLibrary,
            ),
          ),
          Expanded(
            child: _ActionButton(
              icon: Icons.sync_outlined,
              label: 'Track',
              color: muted,
              onPressed: onTracking,
            ),
          ),
          Expanded(
            child: _ActionButton(
              icon: Icons.public,
              label: 'WebView',
              color: muted,
              onPressed: onOpenInBrowser,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Description + genre tags block with expand/collapse — the section
/// behaves like Mihon's `ExpandableMangaDescription`. Collapsed: clamps
/// to 3 lines and shows a chevron-down hint plus a horizontally
/// scrollable chip strip. Expanded: full description + wrapped chips
/// + chevron-up. Tapping anywhere on the block toggles.
class _DescriptionAndTags extends StatefulWidget {
  const _DescriptionAndTags({required this.manga});

  final Manga manga;

  @override
  State<_DescriptionAndTags> createState() => _DescriptionAndTagsState();
}

class _DescriptionAndTagsState extends State<_DescriptionAndTags> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final description = widget.manga.description?.trim();
    final genres = widget.manga.genre ?? const <String>[];
    if ((description == null || description.isEmpty) && genres.isEmpty) {
      return const SizedBox.shrink();
    }
    final hasDescription = description != null && description.isNotEmpty;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasDescription) ...[
                Text(
                  description,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Center(
                  child: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (_expanded)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: genres
                        .map((g) => _GenreChip(text: g))
                        .toList(growable: false),
                  )
                else
                  // Collapsed: single horizontally-scrollable row so the
                  // chip strip doesn't bloat the header.
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: genres.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => _GenreChip(text: genres[i]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
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
      return 'Unknown';
  }
}

IconData _statusIcon(int status) {
  switch (status) {
    case 1:
      return Icons.schedule;
    case 2:
      return Icons.done_all;
    case 3:
      return Icons.attach_money;
    case 4:
      return Icons.done;
    case 5:
      return Icons.close;
    case 6:
      return Icons.pause_circle_outline;
    default:
      return Icons.block_outlined;
  }
}

class _ChapterListHeader extends StatelessWidget {
  const _ChapterListHeader({
    required this.visibleCount,
    required this.totalCount,
    required this.mangaForSheet,
    this.availableScanlators = const {},
    this.excludedScanlators = const {},
  });

  /// Chapters left after filters are applied.
  final int visibleCount;

  /// Total chapter count before filtering. Shown in parens when the
  /// visible count is smaller so it's obvious filters are active.
  final int totalCount;

  /// When non-null the header renders a settings icon that opens the
  /// filter/sort sheet. Skipped on the "0 chapters yet" branch.
  final Manga? mangaForSheet;

  /// Every scanlator that appears on at least one chapter for this
  /// manga. The scanlator-filter sheet uses this to populate its list.
  final Set<String> availableScanlators;

  /// Currently-excluded set. Drives the badge dot on the people icon.
  final Set<String> excludedScanlators;

  @override
  Widget build(BuildContext context) {
    final label = visibleCount == totalCount
        ? '$visibleCount chapters'
        : '$visibleCount of $totalCount chapters';
    final manga = mangaForSheet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (manga != null && availableScanlators.isNotEmpty)
            IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.people_alt_outlined),
                  // Small primary dot when at least one scanlator is
                  // excluded — quick visual cue that the list is
                  // filtered.
                  if (excludedScanlators.isNotEmpty)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Scanlator filter',
              onPressed: () => _openScanlatorFilterSheet(
                context,
                mangaId: manga.id,
                available: availableScanlators,
                excluded: excludedScanlators,
              ),
            ),
          if (manga != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Chapter filter & sort',
              onPressed: () => _openChapterSettingsSheet(context, manga),
            ),
        ],
      ),
    );
  }
}

class _ChapterTile extends ConsumerStatefulWidget {
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
  ConsumerState<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends ConsumerState<_ChapterTile> {
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
    // Honour the per-manga "Display chapter number" toggle. When set, every
    // chapter is labelled by its number even if it has a real title; when
    // unset, fall back to the name and only synthesise a "Chapter N" label
    // for entries with an empty name (matches Mihon's behaviour).
    final showNumber =
        widget.manga.displayMode == Manga.chapterDisplayNumber;
    final title = showNumber || chapter.name.isEmpty
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
                  unawaited(
                    ref.read(trackUpdaterProvider).setLastChapterRead(
                          mangaId: chapter.mangaId,
                          chapterNumber: chapter.chapterNumber,
                        ),
                  );
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
