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
import '../../data/track/track_repository.dart';
import '../../data/track/track_updater.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/category/model/category.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../../domain/source/model/source.dart';
import '../../domain/track/model/track.dart';
import '../common/source_image.dart';
import '../migration/migration_search_screen.dart';
import '../reader/reader_screen.dart';
import '../track/manga_tracking_sheet.dart';
import 'chapter_settings_sheet.dart';
import 'linked_manga_sheet.dart';
import 'manga_cover_viewer.dart';
import 'manga_notes_screen.dart';
import 'scanlator_filter_sheet.dart';

/// Manga details: cover + metadata header followed by the chapter list.
/// Promoted to a stateful widget to own chapter multi-select state — the
/// app bar swaps into a selection bar when at least one chapter row is
/// selected, exposing bulk mark-read / mark-unread / (un)bookmark /
/// download actions. Mirrors Mihon's long-press multi-select flow on the
/// chapter list.
class MangaDetailsScreen extends ConsumerStatefulWidget {
  const MangaDetailsScreen({super.key, required this.mangaId});

  final int mangaId;

  @override
  ConsumerState<MangaDetailsScreen> createState() =>
      _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  final Set<int> _selectedChapterIds = <int>{};

  bool get _selecting => _selectedChapterIds.isNotEmpty;

  void _toggleChapterSelected(int id) {
    setState(() {
      if (!_selectedChapterIds.add(id)) _selectedChapterIds.remove(id);
    });
  }

  void _clearSelection() {
    if (_selectedChapterIds.isEmpty) return;
    setState(_selectedChapterIds.clear);
  }

  void _selectAll(Iterable<int> ids) {
    setState(() {
      _selectedChapterIds
        ..clear()
        ..addAll(ids);
    });
  }

  /// Resolves the selected ids back to `Chapter` rows from the current
  /// stream snapshot. Anything that no longer exists in the snapshot is
  /// dropped silently (rare race when the source-fetch happens to wipe a
  /// row mid-selection).
  List<Chapter> _selectedChapters(List<Chapter> all) {
    if (_selectedChapterIds.isEmpty) return const [];
    final byId = {for (final c in all) c.id: c};
    return [
      for (final id in _selectedChapterIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> _bulkSetRead(List<Chapter> all, bool read) async {
    final chapterRepo = ref.read(chapterRepositoryProvider);
    final picked = _selectedChapters(all);
    for (final c in picked) {
      await chapterRepo.setRead(c.id, read);
    }
    if (read) {
      // Push the highest selected chapter number to trackers, parity
      // with Mihon's per-action sync. We deliberately only push on the
      // mark-read branch — marking unread shouldn't regress trackers.
      final highest = picked.fold<double>(
        -1,
        (m, c) => c.chapterNumber > m ? c.chapterNumber : m,
      );
      if (highest > 0) {
        unawaited(
          ref.read(trackUpdaterProvider).setLastChapterRead(
                mangaId: widget.mangaId,
                chapterNumber: highest,
              ),
        );
      }
    }
    _clearSelection();
  }

  Future<void> _bulkSetBookmark(List<Chapter> all, bool bookmark) async {
    final chapterRepo = ref.read(chapterRepositoryProvider);
    for (final c in _selectedChapters(all)) {
      await chapterRepo.setBookmark(c.id, bookmark);
    }
    _clearSelection();
  }

  Future<void> _bulkDownload(Manga manga, List<Chapter> all) async {
    final downloadRepo = ref.read(downloadRepositoryProvider);
    for (final c in _selectedChapters(all)) {
      await downloadRepo.enqueue(manga, c);
    }
    _clearSelection();
  }

  Future<void> _bulkDeleteDownloads(Manga manga, List<Chapter> all) async {
    final downloadRepo = ref.read(downloadRepositoryProvider);
    for (final c in _selectedChapters(all)) {
      await downloadRepo.deleteDownload(manga.source, manga.id, c.id);
    }
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final mangaRepo = ref.watch(mangaRepositoryProvider);
    final chapterRepo = ref.watch(chapterRepositoryProvider);

    return Scaffold(
      body: StreamBuilder<Manga?>(
        stream: mangaRepo.watchById(widget.mangaId),
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
            stream: chapterRepo.watchByMangaId(widget.mangaId),
            builder: (context, chapSnap) {
              final chapters = chapSnap.data ?? const <Chapter>[];
              final nextUnread = _pickNextUnread(chapters);
              return PopScope(
                canPop: !_selecting,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _clearSelection();
                },
                child: Scaffold(
                  floatingActionButton: _selecting || nextUnread == null
                      ? null
                      : _ContinueReadingFab(
                          manga: manga,
                          chapter: nextUnread,
                          anyRead: chapters.any((c) => c.read),
                        ),
                  body: CustomScrollView(
                  slivers: [
                  if (_selecting)
                    SliverAppBar(
                      pinned: true,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear selection',
                        onPressed: _clearSelection,
                      ),
                      title: Text('${_selectedChapterIds.length} selected'),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          tooltip: 'Select all',
                          onPressed: () =>
                              _selectAll(chapters.map((c) => c.id)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.done_all),
                          tooltip: 'Mark as read',
                          onPressed: () => _bulkSetRead(chapters, true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_done),
                          tooltip: 'Mark as unread',
                          onPressed: () => _bulkSetRead(chapters, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bookmark_add_outlined),
                          tooltip: 'Bookmark',
                          onPressed: () => _bulkSetBookmark(chapters, true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bookmark_remove_outlined),
                          tooltip: 'Remove bookmark',
                          onPressed: () => _bulkSetBookmark(chapters, false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: 'Download',
                          onPressed: () => _bulkDownload(manga, chapters),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete downloads',
                          onPressed: () =>
                              _bulkDeleteDownloads(manga, chapters),
                        ),
                      ],
                    )
                  else
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
                        if (manga.favorite)
                          IconButton(
                            icon: const Icon(Icons.swap_horiz),
                            tooltip: 'Migrate to another source',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MigrationSearchScreen(
                                  sourceManga: manga,
                                ),
                              ),
                            ),
                          ),
                        if (manga.favorite)
                          IconButton(
                            icon: const Icon(Icons.edit_note),
                            tooltip: 'Edit notes',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    MangaNotesScreen(manga: manga),
                              ),
                            ),
                          ),
                        if (manga.favorite)
                          IconButton(
                            icon: const Icon(Icons.update),
                            tooltip: 'Fetch interval',
                            onPressed: () =>
                                _editFetchInterval(context, ref, manga),
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
                  if (manga.favorite)
                    SliverToBoxAdapter(child: _TrackerPreviewBar(manga: manga)),
                  SliverToBoxAdapter(child: _DescriptionAndTags(manga: manga)),
                  if (manga.favorite && manga.notes.trim().isNotEmpty)
                    SliverToBoxAdapter(child: _NotesPreview(manga: manga)),
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
                        selectedIds: _selectedChapterIds,
                        onToggleSelected: _toggleChapterSelected,
                      ),
                    ),
                ],
              ),
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
    required this.selectedIds,
    required this.onToggleSelected,
  });

  final Manga manga;
  final List<Chapter> chapters;
  final ChapterRepository chapterRepo;
  final Set<int> selectedIds;
  final ValueChanged<int> onToggleSelected;

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
              isSelected: selectedIds.contains(sorted[i].id),
              selecting: selectedIds.isNotEmpty,
              onToggleSelected: onToggleSelected,
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

/// Mihon-parity per-manga fetch-interval override. Mihon's discrete
/// picker exposes Default (0) + a handful of day counts + Off (-1).
/// `fetch_interval` (Drift column `calculate_interval`) is read by the
/// background library updater to decide whether a manga is due for a
/// new chapter check.
Future<void> _editFetchInterval(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final picked = await showDialog<int>(
    context: context,
    builder: (_) => _FetchIntervalDialog(current: manga.fetchInterval),
  );
  if (picked == null || picked == manga.fetchInterval) return;
  await ref.read(mangaRepositoryProvider).setFetchInterval(manga.id, picked);
}

class _FetchIntervalDialog extends StatelessWidget {
  const _FetchIntervalDialog({required this.current});

  final int current;

  static const List<({int days, String label})> _options = [
    (days: 0, label: 'Default'),
    (days: 1, label: 'Every day'),
    (days: 2, label: 'Every 2 days'),
    (days: 3, label: 'Every 3 days'),
    (days: 7, label: 'Weekly'),
    (days: 14, label: 'Every 2 weeks'),
    (days: 30, label: 'Monthly'),
    (days: 60, label: 'Every 2 months'),
    (days: 90, label: 'Every 3 months'),
    (days: -1, label: 'Off'),
  ];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Fetch interval'),
      children: [
        RadioGroup<int>(
          groupValue: current,
          onChanged: (v) => Navigator.of(context).pop(v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final opt in _options)
                RadioListTile<int>(
                  value: opt.days,
                  title: Text(opt.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
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
  } else {
    // Mihon-parity duplicate check: warn before adding when there's
    // already a favourited manga with a similar title (substring match,
    // case-insensitive). Lets the user back out if they accidentally
    // re-added an existing series from a different source.
    final dupes = await mangaRepo.findFavoritesWithSimilarTitle(
      manga.id,
      manga.title,
    );
    if (dupes.isNotEmpty && context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Possible duplicate'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Already in your library:'),
              const SizedBox(height: 8),
              for (final d in dupes.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• ${d.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (dupes.length > 5)
                Text('… and ${dupes.length - 5} more'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add anyway'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
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
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MangaCoverViewer(manga: manga),
                        fullscreenDialog: true,
                      ),
                    ),
                    child: _CoverImage(url: manga.thumbnailUrl),
                  ),
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

/// Horizontal chip strip showing each tracker bound to this manga, with
/// its chapter progress and score (when non-zero). Empty when no tracks
/// exist — costs a streaming DB query per detail open. Tapping any chip
/// opens the same tracking sheet as the Track action button so the user
/// can edit progress/score in place.
class _TrackerPreviewBar extends ConsumerWidget {
  const _TrackerPreviewBar({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackRepo = ref.watch(trackRepositoryProvider);
    final registry = ref.watch(trackerRegistryProvider);
    return StreamBuilder<List<Track>>(
      stream: trackRepo.watchByMangaId(manga.id),
      builder: (context, snap) {
        final tracks = snap.data ?? const <Track>[];
        if (tracks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tracks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final t = tracks[i];
                final tracker = registry.byId(t.trackerId);
                final name = tracker?.name ?? 'Tracker ${t.trackerId}';
                return ActionChip(
                  avatar: CircleAvatar(
                    child: Text(
                      name.substring(0, 1),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  label: Text(_chipLabel(name, t)),
                  onPressed: () => _openTrackingSheet(context, manga),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// "AniList · 12/24 · ★8" — drops the score segment when zero (which
  /// is how Mihon's API represents "no score set" for every tracker).
  static String _chipLabel(String name, Track t) {
    final progress = t.totalChapters > 0
        ? '${t.lastChapterRead.toInt()}/${t.totalChapters}'
        : '${t.lastChapterRead.toInt()}';
    if (t.score <= 0) return '$name · $progress';
    final score = t.score == t.score.roundToDouble()
        ? t.score.toInt().toString()
        : t.score.toStringAsFixed(1);
    return '$name · $progress · ★$score';
  }
}

/// Compact preview of the per-manga notes the user has saved. Shown
/// between the description and the chapter list. Tapping anywhere on
/// the block opens the full editor — mirrors Mihon's `MangaNotesSection`
/// minus the markdown-rendered display (v1.0 shows plain text).
class _NotesPreview extends StatelessWidget {
  const _NotesPreview({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaNotesScreen(manga: manga),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Notes',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              manga.notes,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Divider(height: 1),
            ),
          ],
        ),
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
    required this.isSelected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final Manga manga;
  final Chapter chapter;
  final ChapterRepository chapterRepo;
  final DownloadRepository downloadRepo;
  final bool isSelected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

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
      tileColor: widget.isSelected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
          : null,
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
      subtitle: () {
        final note = chapter.bookmarkNote;
        final hasNote = note != null && note.isNotEmpty;
        if (subtitleParts.isEmpty && !hasNote) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitleParts.isNotEmpty) Text(subtitleParts.join(' • ')),
            if (hasNote)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      }(),
      leading: chapter.bookmark
          ? const Icon(Icons.bookmark, size: 20)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DownloadIndicator(state: _downloadState, progress: _progress),
          if (widget.selecting)
            // Hide the per-row popup while a multi-select is in flight —
            // the app bar already exposes the bulk variants of every
            // action and tapping a row should only toggle selection.
            const SizedBox.shrink()
          else
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
                case _ChapterAction.editBookmarkNote:
                  () async {
                    final result = await showBookmarkNoteDialog(
                      context,
                      initialNote: chapter.bookmarkNote ?? '',
                    );
                    if (result == null) return;
                    await chapterRepo.setBookmarkNote(chapter.id, result);
                    // Flip the chapter into the bookmarked state when
                    // the user saves any text — matches Mihon's flow
                    // where editing a note implies bookmarking.
                    if (result.trim().isNotEmpty && !chapter.bookmark) {
                      await chapterRepo.setBookmark(chapter.id, true);
                    }
                  }();
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
              PopupMenuItem(
                value: _ChapterAction.editBookmarkNote,
                child: Text(
                  chapter.bookmarkNote == null || chapter.bookmarkNote!.isEmpty
                      ? 'Add bookmark note'
                      : 'Edit bookmark note',
                ),
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
        if (widget.selecting) {
          widget.onToggleSelected(chapter.id);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              mangaId: chapter.mangaId,
              chapterId: chapter.id,
            ),
          ),
        );
      },
      onLongPress: () => widget.onToggleSelected(chapter.id),
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
  editBookmarkNote,
  download,
  deleteDownload,
}

/// Plain-text bookmark-note dialog. Mihon parity — bookmarking a
/// chapter optionally captures a short note (where you left off, what
/// happened, etc.) that surfaces in the bookmarks UI later. Saving an
/// empty string clears the note.
Future<String?> showBookmarkNoteDialog(
  BuildContext context, {
  required String initialNote,
}) async {
  final controller = TextEditingController(text: initialNote);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Bookmark note'),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 6,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: 'Where did you leave off? Anything to remember?',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
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
