import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/base/base_preferences.dart';
import '../../data/category/category_repository.dart';
import '../../data/chapter/chapter_repository.dart';
import '../../data/cover/cover_cache.dart';
import '../../data/download/download_repository.dart';
import '../../data/library/chapter_swipe_preferences.dart';
import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_update_preference.dart';
import '../../data/library/library_updater.dart';
import '../../data/manga/excluded_scanlators_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/source_repository.dart';
import '../../data/track/track_repository.dart';
import '../../data/track/track_updater.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/category/model/category.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/chapter/service/missing_chapters.dart';
import '../../domain/chapter/service/set_read_status.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../../domain/source/model/source.dart';
import '../../domain/source/model/source_manga.dart';
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

/// Highest recognised volume number across [chapters], or null when none is
/// known — fed to `trackOnMarkRead` so "track by volume" reports the volume.
/// Mirrors Mihon `chapters.mapNotNull { it.volumeNumber }.maxOrNull()`.
double? _maxVolumeNumber(List<Chapter> chapters) {
  double? max;
  for (final c in chapters) {
    final v = c.volumeNumber;
    if (v != null && (max == null || v > max)) max = v;
  }
  return max;
}

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

  /// True while a manual "Refresh" metadata sweep is in flight. Used to
  /// disable the action and swap its icon for a spinner so the user
  /// doesn't double-tap and stack network requests.
  bool _refreshingDetails = false;

  /// Guards the one-shot auto-fetch so opening the details screen only
  /// triggers a single source sweep, even though the build runs again on
  /// every stream emission. Mihon parity with `MangaScreenModel`, which
  /// kicks off `fetchAllFromSource` the first time it sees an
  /// un-initialized manga.
  bool _autoFetchTried = false;

  /// Re-fetches the manga's metadata + chapter list from its source and
  /// persists both. Mihon parity with the "Refresh" overflow action —
  /// covers the case where the source has updated the description /
  /// status / cover etc. since the row was first inserted.
  ///
  /// When [silent] is true the fetch runs without the spinner-swap and
  /// result snackbars; this is the path used by the on-open auto-fetch so
  /// it doesn't flash UI for the routine first-load case.
  Future<void> _refreshMangaFromSource(Manga manga,
      {bool silent = false}) async {
    if (_refreshingDetails) return;
    if (!silent) {
      setState(() => _refreshingDetails = true);
    } else {
      _refreshingDetails = true;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final extRepo = ref.read(extensionRepositoryProvider);
      final mangaRepo = ref.read(mangaRepositoryProvider);
      final chapterRepo = ref.read(chapterRepositoryProvider);
      final source = await extRepo.getSource(manga.source.toString());
      final details = await source.fetchMangaDetails(
        SourceManga(url: manga.url, title: manga.title),
      );
      await mangaRepo.applySourceDetails(manga.id, details);
      final fetched = await source.fetchChapterList(
        SourceManga(url: manga.url, title: manga.title),
      );
      final added = await chapterRepo.syncChaptersWithSource(manga.id, fetched);
      final updater = ref.read(libraryUpdaterProvider);
      await updater.recomputeFetchInterval(
        manga,
        hasNewChapters: added.isNotEmpty,
      );
      await updater.downloadNewChapters(manga, added);
      if (!mounted || silent) return;
      final msg = added.isEmpty
          ? 'Refreshed. No new chapters.'
          : 'Refreshed. ${added.length} new chapter'
              '${added.length == 1 ? '' : 's'}.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted || silent) return;
      messenger.showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    } finally {
      if (silent) {
        _refreshingDetails = false;
      } else if (mounted) {
        setState(() => _refreshingDetails = false);
      }
    }
  }

  /// Fires the one-shot on-open auto-fetch when the manga row has never
  /// been initialized from its source (freshly added from Browse/search).
  /// Deferred to after the current frame so we don't call setState/persist
  /// mid-build.
  void _maybeAutoFetch(Manga manga) {
    if (_autoFetchTried || manga.initialized) return;
    _autoFetchTried = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshMangaFromSource(manga, silent: true);
    });
  }

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

  void _invertSelection(Iterable<int> ids) {
    setState(() {
      for (final id in ids) {
        if (!_selectedChapterIds.add(id)) _selectedChapterIds.remove(id);
      }
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
    final picked = _selectedChapters(all);
    await ref
        .read(setReadStatusProvider)
        .setRead(read: read, chapters: picked);
    if (read) {
      // Push the highest selected chapter number to trackers, parity
      // with Mihon's per-action sync. We deliberately only push on the
      // mark-read branch — marking unread shouldn't regress trackers.
      // Routed through `trackOnMarkRead` so the "Update progress when marked
      // as read" preference (Always / Always ask / Never) is honoured.
      final highest = picked.fold<double>(
        -1,
        (m, c) => c.chapterNumber > m ? c.chapterNumber : m,
      );
      if (highest > 0 && mounted) {
        unawaited(
          trackOnMarkRead(
            ref,
            context,
            mangaId: widget.mangaId,
            chapterNumber: highest,
            volumeNumber: _maxVolumeNumber(picked),
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

  /// Bulk "Mark previous as read" — only meaningful for a single selected
  /// chapter (parity with Kotlin's MangaBottomActionMenu, where the button
  /// is shown only when exactly one chapter is selected). Marks every
  /// strictly-earlier unread chapter as read and pushes the highest such
  /// chapter number to trackers.
  Future<void> _bulkMarkPreviousAsRead(List<Chapter> all) async {
    final picked = _selectedChapters(all);
    if (picked.length != 1) return;
    final chapter = picked.first;
    final earlier = all
        .where((c) => c.chapterNumber < chapter.chapterNumber && !c.read)
        .toList(growable: false);
    await ref
        .read(setReadStatusProvider)
        .setRead(read: true, chapters: earlier);
    if (earlier.isNotEmpty && mounted) {
      final highest =
          earlier.map((c) => c.chapterNumber).reduce((a, b) => a > b ? a : b);
      unawaited(
        trackOnMarkRead(
          ref,
          context,
          mangaId: widget.mangaId,
          chapterNumber: highest,
          volumeNumber: _maxVolumeNumber(earlier),
        ),
      );
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
          _maybeAutoFetch(manga);
          return StreamBuilder<List<Chapter>>(
            stream: chapterRepo.watchByMangaId(widget.mangaId),
            builder: (context, chapSnap) {
              final chapters = chapSnap.data ?? const <Chapter>[];
              final nextUnread = _pickNextUnread(chapters, manga);
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
                  bottomNavigationBar: _selecting
                      ? _ChapterSelectionBar(
                          picked: _selectedChapters(chapters),
                          onBookmark: () => _bulkSetBookmark(chapters, true),
                          onRemoveBookmark: () =>
                              _bulkSetBookmark(chapters, false),
                          onMarkRead: () => _bulkSetRead(chapters, true),
                          onMarkUnread: () => _bulkSetRead(chapters, false),
                          onMarkPrevious: () =>
                              _bulkMarkPreviousAsRead(chapters),
                          onDownload: () => _bulkDownload(manga, chapters),
                          onDelete: () =>
                              _bulkDeleteDownloads(manga, chapters),
                        )
                      : null,
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
                        // Parity with Kotlin: the selection toolbar only
                        // carries Select all + Invert selection. All the
                        // bulk chapter actions live in the bottom action
                        // menu (MangaBottomActionMenu) below.
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          tooltip: 'Select all',
                          onPressed: () =>
                              _selectAll(chapters.map((c) => c.id)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.flip_to_back),
                          tooltip: 'Invert selection',
                          onPressed: () =>
                              _invertSelection(chapters.map((c) => c.id)),
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
                        IconButton(
                          icon: _refreshingDetails
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          tooltip: 'Refresh from source',
                          onPressed: _refreshingDetails
                              ? null
                              : () => _refreshMangaFromSource(manga),
                        ),
                      ],
                    ),
                  SliverToBoxAdapter(child: _MangaInfoBox(manga: manga)),
                  SliverToBoxAdapter(
                    child: _MangaActionRow(
                      manga: manga,
                      onAddToLibrary: () => _toggleFavorite(context, ref, manga),
                      onEditInterval: () =>
                          _editFetchInterval(context, ref, manga),
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
    final groupByVolume = ref.watch(groupChaptersByVolumeProvider);
    final hideMissing = ref.watch(hideMissingChaptersProvider);
    // "Downloaded only" mode pins the per-manga downloaded filter on
    // (Kotlin's Manga.downloadedFilter getter returns ENABLED_IS then).
    final downloadedFilter = ref.watch(downloadedOnlyProvider)
        ? TriState.enabledIs
        : manga.downloadedFilter;
    return StreamBuilder<Set<String>>(
      stream: excludedRepo.watchByMangaId(manga.id),
      builder: (context, excludedSnap) {
        final excluded = excludedSnap.data ?? const <String>{};
        // Only probe the filesystem when the downloaded filter axis is
        // actually engaged. Common path stays sync.
        if (downloadedFilter == TriState.disabled) {
          return _buildBody(context, excluded, null, downloadedFilter,
              downloadRepo, groupByVolume, hideMissing);
        }
        // Cached: the chapter list rebuilds on every selection tap and
        // download event; re-issuing the filesystem walk per rebuild made
        // the screen lag whenever the downloaded filter was engaged.
        return _DownloadedIdsLoader(
          downloadRepo: downloadRepo,
          sourceId: manga.source,
          mangaId: manga.id,
          builder: (context, ids) {
            return _buildBody(
              context,
              excluded,
              ids ?? const <int>{},
              downloadedFilter,
              downloadRepo,
              groupByVolume,
              hideMissing,
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
    TriState downloadedFilter,
    DownloadRepository downloadRepo,
    bool groupByVolume,
    bool hideMissing,
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
      // Local-source chapters count as downloaded (Kotlin applies
      // `|| manga.isLocal()` to the downloaded predicate).
      final downloadedOk = downloadedIds == null
          ? true
          : applyTriState(
              downloadedFilter,
              () => downloadedIds.contains(c.id) || manga.source == 0,
            );
      return unreadOk && bookmarkedOk && downloadedOk;
    }).toList(growable: false);

    // Sort via the shared Mihon `getChapterSort` port. NOTE the SOURCE case
    // is intentionally inverted vs the other modes (sourceOrder 0 == newest),
    // so descending source order shows the NEWEST chapter at the top — the
    // Mihon default — rather than the oldest.
    final sorted = [...filtered]
      ..sort((a, b) => _chapterSortCompare(a, b, manga));

    // Build the interleaved render list:
    //  - "Missing N chapters" separators wherever there's a numeric gap
    //    between adjacent chapters (unless hidden) — 1:1 with Mihon's
    //    chapterListItems.insertSeparators (MangaScreenModel).
    //  - Volume header rows each time the volume number changes (when "Group
    //    chapters by volume" is on) — 1:1 with MangaScreen's VolumeHeaderItem.
    // A NaN sentinel (which never equals any real value or null) forces a
    // volume header before the first chapter.
    final List<Object> rendered;
    if (groupByVolume || !hideMissing) {
      rendered = <Object>[];
      double? lastVolume = double.nan;
      for (var i = 0; i < sorted.length; i++) {
        final c = sorted[i];
        if (!hideMissing) {
          final missing = _missingCountBetween(
            before: i > 0 ? sorted[i - 1] : null,
            after: c,
            manga: manga,
          );
          if (missing > 0) rendered.add(_MissingCountItem(missing));
        }
        if (groupByVolume && c.volumeNumber != lastVolume) {
          rendered.add(_VolumeHeaderItem(c.volumeNumber));
          lastVolume = c.volumeNumber;
        }
        rendered.add(c);
      }
      if (!hideMissing && sorted.isNotEmpty) {
        final missing = _missingCountBetween(
          before: sorted.last,
          after: null,
          manga: manga,
        );
        if (missing > 0) rendered.add(_MissingCountItem(missing));
      }
    } else {
      rendered = sorted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChapterListHeader(
          visibleCount: sorted.length,
          totalCount: chapters.length,
          mangaForSheet: manga,
          availableScanlators: availableScanlators,
          excludedScanlators: excluded,
          onBulkDownload: (scope, count) {
            Iterable<Chapter> target;
            switch (scope) {
              case _DownloadScope.next:
                // 1:1 with Mihon's getUnreadChaptersSorted: sort by
                // getChapterSort, reverse when the manga sorts descending,
                // so the EARLIEST unread chapters in reading order are
                // taken first, then take N.
                final sorted = chapters.where((c) => !c.read).toList()
                  ..sort((a, b) => _chapterSortCompare(a, b, manga));
                final ordered = manga.sortDescending()
                    ? sorted.reversed.toList()
                    : sorted;
                target = count == null ? ordered : ordered.take(count);
              case _DownloadScope.unread:
                // getUnreadChapters: every unread chapter (order is
                // irrelevant since all get enqueued).
                target = chapters.where((c) => !c.read);
              case _DownloadScope.bookmarked:
                // getBookmarkedChapters.
                target = chapters.where((c) => c.bookmark);
            }
            for (final c in target) {
              unawaited(downloadRepo.enqueue(manga, c));
            }
          },
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
            itemCount: rendered.length,
            itemBuilder: (_, i) {
              final item = rendered[i];
              if (item is _VolumeHeaderItem) {
                return _VolumeHeaderRow(volumeNumber: item.volumeNumber);
              }
              if (item is _MissingCountItem) {
                return _MissingCountRow(count: item.count);
              }
              final chapter = item as Chapter;
              return _ChapterTile(
                manga: manga,
                chapter: chapter,
                chapterRepo: chapterRepo,
                downloadRepo: downloadRepo,
                isSelected: selectedIds.contains(chapter.id),
                selecting: selectedIds.isNotEmpty,
                onToggleSelected: onToggleSelected,
                // Pass the full (unfiltered, unsorted) chapter list so the
                // "Mark previous as read" affordance acts over every chapter
                // earlier in reading order, not just the ones the current
                // filter happens to show.
                allChapters: chapters,
              );
            },
          ),
      ],
    );
  }
}

/// Marker entry interleaved into the chapter list when "Group chapters by
/// volume" is on. Carries the volume number of the group that follows
/// (null == "Unknown volume"). Mirrors Mihon's private `VolumeHeaderItem`.
class _VolumeHeaderItem {
  const _VolumeHeaderItem(this.volumeNumber);
  final double? volumeNumber;
}

/// Marker entry interleaved into the chapter list for a numeric gap between
/// two adjacent chapters. Carries the number of missing chapters. Mirrors
/// Mihon's private `ChapterList.MissingCount`.
class _MissingCountItem {
  const _MissingCountItem(this.count);
  final int count;
}

/// Number of chapters missing between two adjacent chapter-list entries,
/// 1:1 with Mihon's `chapterListItems.insertSeparators`
/// (MangaScreenModel): the lower/higher pair is chosen by the manga's sort
/// direction, the leading edge reports gaps before chapter 1, and unknown
/// (negative) chapter numbers contribute no gap.
int _missingCountBetween({
  required Chapter? before,
  required Chapter? after,
  required Manga manga,
}) {
  final desc = manga.sortDescending();
  final lower = desc ? after : before;
  final higher = desc ? before : after;
  if (higher == null) return 0;
  if (lower == null) {
    if (!higher.isRecognizedNumber) return 0;
    final c = higher.chapterNumber.floor() - 1;
    return c < 0 ? 0 : c;
  }
  return calculateChapterGap(higher, lower);
}

/// Missing-chapter separator row. Mirrors Mihon's
/// `MissingChapterCountListItem`: a dimmed "Missing N chapters" label flanked
/// by horizontal dividers.
class _MissingCountRow extends StatelessWidget {
  const _MissingCountRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == 1 ? 'Missing 1 chapter' : 'Missing $count chapters';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// Volume separator row. Mirrors Mihon's `VolumeHeaderListItem`: a primary
/// coloured title-small label ("Volume N" / "Unknown volume") padded 16/8.
class _VolumeHeaderRow extends StatelessWidget {
  const _VolumeHeaderRow({required this.volumeNumber});

  final double? volumeNumber;

  String _label() {
    final v = volumeNumber;
    if (v == null) return 'Unknown volume';
    final n = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return 'Volume $n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        _label(),
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// Comparator matching Mihon's `getChapterSort` (ChapterSort.kt) exactly,
/// including its source-order quirk: because sources return chapters
/// newest-first (so `sourceOrder == 0` is the NEWEST chapter), the SOURCE
/// case inverts its direction relative to the number/date/alphabet cases.
int _chapterSortCompare(Chapter a, Chapter b, Manga manga) {
  final desc = manga.sortDescending();
  switch (manga.sorting) {
    case Manga.chapterSortingNumber:
      return desc
          ? b.chapterNumber.compareTo(a.chapterNumber)
          : a.chapterNumber.compareTo(b.chapterNumber);
    case Manga.chapterSortingUploadDate:
      return desc
          ? b.dateUpload.compareTo(a.dateUpload)
          : a.dateUpload.compareTo(b.dateUpload);
    case Manga.chapterSortingAlphabet:
      return desc
          ? b.name.toLowerCase().compareTo(a.name.toLowerCase())
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    default: // chapterSortingSource
      return desc
          ? a.sourceOrder.compareTo(b.sourceOrder)
          : b.sourceOrder.compareTo(a.sourceOrder);
  }
}

/// Returns the next chapter the user should read, or null if every
/// chapter is already marked read (or the list is empty).
///
/// 1:1 port of Mihon's `List<Chapter>.getNextUnread` (ChapterGetNextUnread.kt):
/// sort the chapters with the manga's `getChapterSort`, then pick the LAST
/// unread when the manga sorts descending (else the FIRST). Net effect across
/// every sort mode: the OLDEST unread chapter in reading order — e.g. Ch.1 on
/// a fresh manga, not the newest chapter. Excluded scanlators are NOT filtered
/// here — Mihon shows the FAB even when filters hide chapters, and we match it.
Chapter? _pickNextUnread(List<Chapter> chapters, Manga manga) {
  final unread = chapters.where((c) => !c.read).toList();
  if (unread.isEmpty) return null;
  unread.sort((a, b) => _chapterSortCompare(a, b, manga));
  return manga.sortDescending() ? unread.last : unread.first;
}

/// Floating action button that jumps straight into the next unread
/// chapter. Label flips between "Start" (no chapters read yet) and
/// "Resume" (at least one chapter is already read) — verbatim Mihon
/// strings `action_start` / `action_resume`.
/// Bottom action menu shown while chapters are multi-selected, mirroring
/// Kotlin's `MangaBottomActionMenu`. Button order and conditional
/// visibility follow the Kotlin source: Bookmark, Remove bookmark, Mark as
/// read, Mark as unread, Mark previous as read (single selection only),
/// Download, Delete.
class _ChapterSelectionBar extends StatelessWidget {
  const _ChapterSelectionBar({
    required this.picked,
    required this.onBookmark,
    required this.onRemoveBookmark,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onMarkPrevious,
    required this.onDownload,
    required this.onDelete,
  });

  final List<Chapter> picked;
  final VoidCallback onBookmark;
  final VoidCallback onRemoveBookmark;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onMarkPrevious;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final showBookmark = picked.any((c) => !c.bookmark);
    final showRemoveBookmark =
        picked.isNotEmpty && picked.every((c) => c.bookmark);
    final showMarkRead = picked.any((c) => !c.read);
    final showMarkUnread = picked.any((c) => c.read || c.lastPageRead > 0);
    final showMarkPrevious = picked.length == 1;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (showBookmark)
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Bookmark',
              onPressed: onBookmark,
            ),
          if (showRemoveBookmark)
            IconButton(
              icon: const Icon(Icons.bookmark_remove_outlined),
              tooltip: 'Remove bookmark',
              onPressed: onRemoveBookmark,
            ),
          if (showMarkRead)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark as read',
              onPressed: onMarkRead,
            ),
          if (showMarkUnread)
            IconButton(
              icon: const Icon(Icons.remove_done),
              tooltip: 'Mark as unread',
              onPressed: onMarkUnread,
            ),
          if (showMarkPrevious)
            IconButton(
              icon: const Icon(Icons.playlist_add_check),
              tooltip: 'Mark previous as read',
              onPressed: onMarkPrevious,
            ),
          // Download/Delete are always offered: per-chapter download state
          // is tracked inside each row, so we can't cheaply compute the
          // "any not downloaded" / "any downloaded" gates the Kotlin menu
          // uses. Functionality is identical; only the conditional hiding
          // is relaxed.
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download',
            onPressed: onDownload,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete downloads',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

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
      label: Text(anyRead ? 'Resume' : 'Start'),
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

/// Card-based duplicate-warning dialog shown before flipping a new
/// manga's `favorite=1` bit, when one or more favourited series share a
/// fuzzy-matching title. Each row is tappable: tapping opens that
/// duplicate's `MangaDetailsScreen` (so the user can pick it instead of
/// re-adding a parallel copy) and dismisses the dialog as Cancel.
/// Bottom buttons let the user back out or proceed with the add.
class _DuplicateMangaDialog extends StatelessWidget {
  const _DuplicateMangaDialog({required this.duplicates});

  final List<Manga> duplicates;

  static const int _maxRows = 5;

  @override
  Widget build(BuildContext context) {
    final shown = duplicates.take(_maxRows).toList(growable: false);
    final extras = duplicates.length - shown.length;
    return AlertDialog(
      title: const Text('Possible duplicate'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Already in your library:'),
            ),
            for (final d in shown)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: SizedBox(
                  width: 40,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _CoverImage(mangaId: d.id, url: d.thumbnailUrl),
                  ),
                ),
                title: Text(
                  d.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: (d.author != null && d.author!.isNotEmpty)
                    ? Text(
                        d.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () {
                  Navigator.of(context).pop(false);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MangaDetailsScreen(mangaId: d.id),
                    ),
                  );
                },
              ),
            if (extras > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                child: Text(
                  '… and $extras more',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Add anyway'),
        ),
      ],
    );
  }
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

/// Loads the downloaded-chapter id set once per manga identity instead of on
/// every rebuild (the previous inline FutureBuilder re-walked the downloads
/// tree per frame while the downloaded filter was engaged).
class _DownloadedIdsLoader extends StatefulWidget {
  const _DownloadedIdsLoader({
    required this.downloadRepo,
    required this.sourceId,
    required this.mangaId,
    required this.builder,
  });

  final DownloadRepository downloadRepo;
  final int sourceId;
  final int mangaId;
  final Widget Function(BuildContext context, Set<int>? ids) builder;

  @override
  State<_DownloadedIdsLoader> createState() => _DownloadedIdsLoaderState();
}

class _DownloadedIdsLoaderState extends State<_DownloadedIdsLoader> {
  Set<int>? _ids;
  StreamSubscription<DownloadEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _probe();
    // Keep the set fresh as downloads complete / get deleted while the
    // screen is open, without polling per rebuild.
    _sub = widget.downloadRepo.events.listen((e) {
      if (e.state == DownloadState.completed ||
          e.state == DownloadState.deleted) {
        _probe();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DownloadedIdsLoader old) {
    super.didUpdateWidget(old);
    if (old.mangaId != widget.mangaId || old.sourceId != widget.sourceId) {
      _probe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _probe() async {
    final ids = await widget.downloadRepo.listDownloadedChapterIds(
      widget.sourceId,
      widget.mangaId,
    );
    if (mounted) setState(() => _ids = ids);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _ids);
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
        builder: (ctx) => _DuplicateMangaDialog(duplicates: dupes),
      );
      if (go != true) return;
    }
    // Default-category routing (Kotlin MangaScreenModel.toggleFavorite):
    // a configured category gets the manga directly; "Default" (0) or no
    // categories favourites without membership; "Always ask" (-1, the
    // default) opens the category sheet and only favourites on confirm.
    final categoryRepo = ref.read(categoryRepositoryProvider);
    final all = await categoryRepo.getAll();
    final userCategories =
        all.where((c) => !c.isSystemCategory).toList(growable: false);
    final defaultCategoryId = ref.read(defaultCategoryProvider);
    Category? defaultCategory;
    for (final c in userCategories) {
      if (c.id == defaultCategoryId) {
        defaultCategory = c;
        break;
      }
    }
    if (defaultCategory != null) {
      await mangaRepo.setFavorite(manga.id, true);
      await categoryRepo.setCategoriesForManga(manga.id, {defaultCategory.id});
    } else if (defaultCategoryId == 0 || userCategories.isEmpty) {
      await mangaRepo.setFavorite(manga.id, true);
      await categoryRepo.setCategoriesForManga(manga.id, const <int>{});
    } else {
      if (!context.mounted) return;
      final selection = await showModalBottomSheet<Set<int>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => _CategorySelector(
          categories: userCategories,
          initiallySelected: const <int>{},
        ),
      );
      if (selection == null) return;
      await mangaRepo.setFavorite(manga.id, true);
      await categoryRepo.setCategoriesForManga(manga.id, selection);
    }
    return;
  }
  // Remove from library; also clear category memberships so the manga
  // doesn't reappear in a category-filtered view if it's added back.
  await mangaRepo.setFavorite(manga.id, false);
  final categoryRepo = ref.read(categoryRepositoryProvider);
  await categoryRepo.setCategoriesForManga(manga.id, const <int>{});
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
                    child: _CoverImage(mangaId: manga.id, url: manga.thumbnailUrl),
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

class _Backdrop extends ConsumerWidget {
  const _Backdrop({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url =
        ref.watch(coverCacheProvider).coverUrlFor(manga.id, manga.thumbnailUrl);
    final bg = Theme.of(context).colorScheme.surface;
    if (url == null || url.isEmpty) {
      return Container(color: bg);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blur the dimmed cover directly with an [ImageFiltered] rather than
        // a [BackdropFilter]: the latter has no clip inside a scroll view and
        // blurs every layer painted behind it — including the chapter list as
        // it scrolls up under this header, which washed the list out.
        // [ImageFiltered] only filters its own child, so the bleed is gone.
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Opacity(
            opacity: 0.25,
            child: SourceImage(
              cacheWidth: 480,
              url: url,
              fit: BoxFit.cover,
              placeholder: (_) => Container(color: bg),
              errorWidget: (_, _) => Container(color: bg),
            ),
          ),
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

class _CoverImage extends ConsumerWidget {
  const _CoverImage({required this.mangaId, required this.url});

  final int mangaId;
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    final resolved = ref.watch(coverCacheProvider).coverUrlFor(mangaId, url);
    if (resolved == null || resolved.isEmpty) {
      return Container(color: placeholder);
    }
    return SourceImage(
      cacheWidth: 480,
      url: resolved,
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
    required this.onEditInterval,
    required this.onTracking,
    required this.onOpenInBrowser,
  });

  final Manga manga;
  final VoidCallback onAddToLibrary;
  final VoidCallback onEditInterval;
  final VoidCallback onTracking;
  final VoidCallback onOpenInBrowser;

  /// Mirrors Kotlin's MangaActionRow "Next Update" label: "N/A" for
  /// finished series (no expected update), "Update soon" within a day, or
  /// the whole-day count otherwise.
  String _nextUpdateLabel() {
    final next = manga.expectedNextUpdate;
    if (next == null) return 'N/A';
    final days = next.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Update soon';
    return days == 1 ? '1 day' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    // A manually-set interval is stored as a negative value (Kotlin
    // parity); highlight the button with the accent colour in that case.
    final customInterval = manga.fetchInterval < 0;
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
          if (manga.favorite)
            Expanded(
              child: _ActionButton(
                icon: Icons.hourglass_empty,
                label: _nextUpdateLabel(),
                color: customInterval ? primary : muted,
                onPressed: onEditInterval,
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
    this.onBulkDownload,
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

  /// Bulk-download callback. `scope` selects which chapters to enqueue;
  /// `count` carries N for [_DownloadScope.next] and is ignored otherwise.
  /// A null callback hides the menu entirely.
  final void Function(_DownloadScope scope, int? count)? onBulkDownload;

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
          if (manga != null && onBulkDownload != null)
            PopupMenuButton<(_DownloadScope, int?)>(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download',
              onSelected: (v) => onBulkDownload!(v.$1, v.$2),
              // Parity with Kotlin DownloadDropdownMenu: Next 1/5/10/25,
              // Unread, Bookmarked — always shown, no unread-count gating.
              itemBuilder: (_) => [
                for (final n in const [1, 5, 10, 25])
                  PopupMenuItem<(_DownloadScope, int?)>(
                    value: (_DownloadScope.next, n),
                    child: Text(n == 1 ? 'Next chapter' : 'Next $n chapters'),
                  ),
                const PopupMenuItem<(_DownloadScope, int?)>(
                  value: (_DownloadScope.unread, null),
                  child: Text('Unread'),
                ),
                const PopupMenuItem<(_DownloadScope, int?)>(
                  value: (_DownloadScope.bookmarked, null),
                  child: Text('Bookmarked'),
                ),
              ],
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
    required this.allChapters,
  });

  final Manga manga;
  final Chapter chapter;
  final ChapterRepository chapterRepo;
  final DownloadRepository downloadRepo;
  final bool isSelected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;
  final List<Chapter> allChapters;

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
    final tile = ListTile(
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
                  unawaited(
                    ref.read(setReadStatusProvider).setRead(
                      read: true,
                      chapters: [chapter],
                    ),
                  );
                  unawaited(
                    trackOnMarkRead(
                      ref,
                      context,
                      mangaId: chapter.mangaId,
                      chapterNumber: chapter.chapterNumber,
                      volumeNumber: chapter.volumeNumber,
                    ),
                  );
                case _ChapterAction.markUnread:
                  unawaited(
                    ref.read(setReadStatusProvider).setRead(
                      read: false,
                      chapters: [chapter],
                    ),
                  );
                case _ChapterAction.markPreviousAsRead:
                  () async {
                    // Strict less-than: the current chapter is not
                    // included (Mihon parity — that's what
                    // `markPreviousChapterRead` does). Skip rows already
                    // marked read to avoid pointless writes.
                    final earlier = widget.allChapters
                        .where((c) =>
                            c.chapterNumber < chapter.chapterNumber && !c.read)
                        .toList(growable: false);
                    await ref
                        .read(setReadStatusProvider)
                        .setRead(read: true, chapters: earlier);
                    if (earlier.isNotEmpty && context.mounted) {
                      // Push the highest chapter number we just marked
                      // (which is strictly less than `chapter`) to
                      // trackers so progress stays consistent.
                      final highest = earlier
                          .map((c) => c.chapterNumber)
                          .reduce((a, b) => a > b ? a : b);
                      unawaited(
                        trackOnMarkRead(
                          ref,
                          context,
                          mangaId: chapter.mangaId,
                          chapterNumber: highest,
                          volumeNumber: _maxVolumeNumber(earlier),
                        ),
                      );
                    }
                  }();
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
              if (widget.allChapters.any((c) =>
                  c.chapterNumber < chapter.chapterNumber && !c.read))
                const PopupMenuItem(
                  value: _ChapterAction.markPreviousAsRead,
                  child: Text('Mark previous as read'),
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
    // Swipe actions (Kotlin MangaChapterListItem's swipeable rows). The row
    // never actually dismisses — confirmDismiss performs the action and
    // returns false, mirroring Kotlin's swipe-to-trigger semantics.
    final swipeStart =
        ChapterSwipeAction.fromName(ref.watch(swipeToStartActionProvider));
    final swipeEnd =
        ChapterSwipeAction.fromName(ref.watch(swipeToEndActionProvider));
    final startEnabled = swipeStart != ChapterSwipeAction.disabled;
    final endEnabled = swipeEnd != ChapterSwipeAction.disabled;
    if (widget.selecting || (!startEnabled && !endEnabled)) return tile;
    return Dismissible(
      key: ValueKey('chapter-swipe-${chapter.id}'),
      direction: startEnabled && endEnabled
          ? DismissDirection.horizontal
          : startEnabled
              ? DismissDirection.endToStart
              : DismissDirection.startToEnd,
      background: _swipeBackground(swipeEnd, AlignmentDirectional.centerStart),
      secondaryBackground:
          _swipeBackground(swipeStart, AlignmentDirectional.centerEnd),
      confirmDismiss: (dir) async {
        _performSwipe(
          dir == DismissDirection.startToEnd ? swipeEnd : swipeStart,
        );
        return false;
      },
      child: tile,
    );
  }

  /// Coloured strip + action icon revealed behind a swiping row. Icon choice
  /// matches Kotlin `getSwipeAction` (done/remove-done, bookmark-add/remove,
  /// download-state-dependent download/cancel/delete).
  Widget _swipeBackground(
    ChapterSwipeAction action,
    AlignmentDirectional alignment,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final IconData icon;
    switch (action) {
      case ChapterSwipeAction.toggleRead:
        icon = widget.chapter.read ? Icons.remove_done : Icons.done;
      case ChapterSwipeAction.toggleBookmark:
        icon = widget.chapter.bookmark
            ? Icons.bookmark_remove_outlined
            : Icons.bookmark_add_outlined;
      case ChapterSwipeAction.download:
        icon = switch (_downloadState) {
          DownloadState.completed => Icons.delete_outlined,
          DownloadState.queued ||
          DownloadState.downloading =>
            Icons.file_download_off_outlined,
          _ => Icons.download_outlined,
        };
      case ChapterSwipeAction.disabled:
        return const SizedBox.shrink();
    }
    return Container(
      color: scheme.primaryContainer,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: scheme.onPrimaryContainer),
    );
  }

  void _performSwipe(ChapterSwipeAction action) {
    final chapter = widget.chapter;
    switch (action) {
      case ChapterSwipeAction.toggleRead:
        unawaited(
          ref
              .read(setReadStatusProvider)
              .setRead(read: !chapter.read, chapters: [chapter]),
        );
        if (!chapter.read) {
          unawaited(
            trackOnMarkRead(
              ref,
              context,
              mangaId: chapter.mangaId,
              chapterNumber: chapter.chapterNumber,
              volumeNumber: chapter.volumeNumber,
            ),
          );
        }
      case ChapterSwipeAction.toggleBookmark:
        unawaited(
          widget.chapterRepo.setBookmark(chapter.id, !chapter.bookmark),
        );
      case ChapterSwipeAction.download:
        switch (_downloadState) {
          case DownloadState.completed:
            unawaited(
              widget.downloadRepo.deleteDownload(
                widget.manga.source,
                widget.manga.id,
                chapter.id,
              ),
            );
          case DownloadState.queued || DownloadState.downloading:
            widget.downloadRepo.cancel(chapter.id);
          default:
            unawaited(widget.downloadRepo.enqueue(widget.manga, chapter));
        }
      case ChapterSwipeAction.disabled:
        break;
    }
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
  markPreviousAsRead,
  bookmark,
  unbookmark,
  editBookmarkNote,
  download,
  deleteDownload,
}

/// Bulk-download scopes offered by the chapter-header download menu,
/// mirroring Kotlin's DownloadAction (NEXT_N / UNREAD / BOOKMARKED).
enum _DownloadScope { next, unread, bookmarked }

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
      // Whole-queue lifecycle events don't carry a chapterId — never
      // reach a per-chapter indicator. Render nothing.
      case DownloadState.queuePaused:
      case DownloadState.queueResumed:
      case DownloadState.networkWaiting:
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
