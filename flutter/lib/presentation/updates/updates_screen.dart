import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/library/library_updater.dart';
import '../../data/updates/updates_filter_prefs.dart';
import '../../data/updates/updates_repository.dart';
import '../../domain/manga/model/tri_state.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';
import '../reader/reader_screen.dart';
import '../upcoming/upcoming_screen.dart';

/// Updates tab -- streams `updatesView` (newly fetched chapters in
/// favourited manga). Mirrors the Kotlin UpdatesTab presentation: cover
/// thumbnail, manga title, chapter name, with read/bookmark/scanlator-mute
/// state baked into the visual treatment.
///
/// Pull-to-refresh and the app-bar refresh button both run a foreground
/// library update via `LibraryUpdater.updateAll`; the workmanager
/// schedule continues to run independently in the background.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  bool _updating = false;
  final Set<int> _selectedChapterIds = <int>{};
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  bool get _selecting => _selectedChapterIds.isNotEmpty;

  void _toggleSelected(int chapterId) {
    setState(() {
      if (!_selectedChapterIds.add(chapterId)) {
        _selectedChapterIds.remove(chapterId);
      }
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

  Future<void> _bulkSetRead(List<LibraryUpdate> visible, bool read) async {
    final repo = ref.read(chapterRepositoryProvider);
    final ids = visible
        .where((u) => _selectedChapterIds.contains(u.chapterId))
        .map((u) => u.chapterId)
        .toList(growable: false);
    for (final id in ids) {
      await repo.setRead(id, read);
    }
    _clearSelection();
  }

  Future<void> _bulkSetBookmark(
    List<LibraryUpdate> visible,
    bool bookmark,
  ) async {
    final repo = ref.read(chapterRepositoryProvider);
    final ids = visible
        .where((u) => _selectedChapterIds.contains(u.chapterId))
        .map((u) => u.chapterId)
        .toList(growable: false);
    for (final id in ids) {
      await repo.setBookmark(id, bookmark);
    }
    _clearSelection();
  }

  Future<void> _refresh() async {
    if (_updating) return;
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updater = ref.read(libraryUpdaterProvider);
      final result = await updater.updateAll();
      if (!mounted) return;
      final msg = result.newChapters == 0
          ? 'No new chapters found.'
          : '${result.newChapters} new chapter'
              '${result.newChapters == 1 ? '' : 's'} added.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(updatesRepositoryProvider);
    final filters = ref.watch(updatesFiltersProvider);
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<LibraryUpdate>>(
      stream: repo.watchAll(),
      builder: (context, snapshot) {
        final updates = snapshot.data ?? const <LibraryUpdate>[];
        // Case-insensitive substring match against manga title — same
        // shape as the History tab search field. Empty query is a fast
        // pass-through (no allocation, no per-row toLower).
        final q = _query.toLowerCase();
        final visible = updates.where((u) {
          if (q.isNotEmpty && !u.mangaTitle.toLowerCase().contains(q)) {
            return false;
          }
          if (!applyTriState(filters.unread, () => !u.read)) return false;
          if (!applyTriState(filters.bookmark, () => u.bookmark)) {
            return false;
          }
          if (filters.hideMutedScanlators && u.isScanlatorMuted) {
            return false;
          }
          return true;
        }).toList(growable: false);
        return PopScope(
          // System back closes the in-flight thing first: selection >
          // search > pop.
          canPop: !_selecting && !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_selecting) {
              _clearSelection();
            } else if (_searching) {
              _closeSearch();
            }
          },
          child: Scaffold(
            appBar: _selecting
                ? AppBar(
                    backgroundColor: scheme.primaryContainer,
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear selection',
                      onPressed: _clearSelection,
                    ),
                    title: Text('${_selectedChapterIds.length} selected'),
                    actions: [
                      if (_selectedChapterIds.length == 1)
                        IconButton(
                          icon: const Icon(Icons.menu_book_outlined),
                          tooltip: 'Open manga details',
                          onPressed: () {
                            final id = _selectedChapterIds.single;
                            final pick = visible.firstWhere(
                              (u) => u.chapterId == id,
                              orElse: () => updates.firstWhere(
                                (u) => u.chapterId == id,
                              ),
                            );
                            _clearSelection();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MangaDetailsScreen(
                                  mangaId: pick.mangaId,
                                ),
                              ),
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.select_all),
                        tooltip: 'Select all',
                        onPressed: () =>
                            _selectAll(visible.map((u) => u.chapterId)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.done_all),
                        tooltip: 'Mark as read',
                        onPressed: () => _bulkSetRead(visible, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_done),
                        tooltip: 'Mark as unread',
                        onPressed: () => _bulkSetRead(visible, false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: 'Bookmark',
                        onPressed: () => _bulkSetBookmark(visible, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmark_remove_outlined),
                        tooltip: 'Remove bookmark',
                        onPressed: () => _bulkSetBookmark(visible, false),
                      ),
                    ],
                  )
                : AppBar(
                    title: _searching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Search updates',
                              border: InputBorder.none,
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                            textInputAction: TextInputAction.search,
                            onChanged: (v) =>
                                setState(() => _query = v.trim()),
                          )
                        : const Text('Updates'),
                    leading: _searching
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _closeSearch,
                          )
                        : null,
                    actions: [
                      if (_searching && _query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear query',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      else if (!_searching) ...[
                        IconButton(
                          icon: const Icon(Icons.calendar_month),
                          tooltip: 'Upcoming',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const UpcomingScreen(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search updates',
                          onPressed: _openSearch,
                        ),
                      ],
                      IconButton(
                        icon: Icon(
                          Icons.filter_list,
                          color: filters.isActive ? scheme.primary : null,
                        ),
                        tooltip: 'Filter updates',
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const _UpdatesFilterDialog(),
                        ),
                      ),
                      IconButton(
                        icon: _updating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Update library',
                        onPressed: _updating ? null : _refresh,
                      ),
                    ],
                  ),
            body: Builder(
              builder: (_) {
                if (snapshot.hasError) {
                  return _Message(
                    text: 'Failed to load updates: ${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: visible.isEmpty
                      ? ListView(
                          // ListView so RefreshIndicator still triggers on overscroll.
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _Message(
                              text: _query.isNotEmpty
                                  ? 'No updates match the query.'
                                  : filters.isActive
                                      ? 'No updates match the current filter.'
                                      : 'No new chapters.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _UpdateTile(
                            update: visible[i],
                            selected: _selectedChapterIds
                                .contains(visible[i].chapterId),
                            selecting: _selecting,
                            onToggleSelected: _toggleSelected,
                          ),
                        ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Three-axis filter dialog: unread (tri), bookmark (tri), and a flip
/// for hiding muted-scanlator rows entirely. Each tri-state cycles
/// disabled → enabledIs → enabledNot → disabled on tap to keep the
/// dialog compact (Mihon uses three icons; we use a single rotating
/// `Icon` for the same effect).
class _UpdatesFilterDialog extends ConsumerWidget {
  const _UpdatesFilterDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(updatesFiltersProvider);
    final notifier = ref.read(updatesFiltersProvider.notifier);

    TriState next(TriState v) {
      switch (v) {
        case TriState.disabled:
          return TriState.enabledIs;
        case TriState.enabledIs:
          return TriState.enabledNot;
        case TriState.enabledNot:
          return TriState.disabled;
      }
    }

    Widget triRow(
      String label,
      TriState value,
      ValueChanged<TriState> onChanged,
    ) {
      IconData icon;
      String stateText;
      switch (value) {
        case TriState.disabled:
          icon = Icons.check_box_outline_blank;
          stateText = 'Off';
        case TriState.enabledIs:
          icon = Icons.check_box;
          stateText = 'Include';
        case TriState.enabledNot:
          icon = Icons.disabled_by_default;
          stateText = 'Exclude';
      }
      return ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(stateText),
        onTap: () => onChanged(next(value)),
      );
    }

    return AlertDialog(
      title: const Text('Filter updates'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            triRow('Unread', filters.unread, notifier.setUnread),
            triRow('Bookmarked', filters.bookmark, notifier.setBookmark),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Hide muted-scanlator rows'),
              subtitle: const Text(
                'When off, muted rows still appear with strikethrough.',
              ),
              value: filters.hideMutedScanlators,
              onChanged: notifier.setHideMutedScanlators,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile({
    required this.update,
    required this.selected,
    required this.selecting,
    required this.onToggleSelected,
  });

  final LibraryUpdate update;
  final bool selected;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final readColor = theme.disabledColor;
    final defaultColor = theme.colorScheme.onSurface;
    final muted = update.isScanlatorMuted;
    final subtitleBits = <String>[
      update.chapterName,
      if (update.scanlator != null && update.scanlator!.isNotEmpty)
        update.scanlator!,
      if (update.isLinkedAttribution) 'linked source',
    ];
    return ListTile(
      // Selected rows pick up the primaryContainer wash to match the
      // selection app bar — same visual key used by the chapter
      // multi-select on the manga details screen.
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      leading: _Thumb(url: update.thumbnailUrl),
      title: Text(
        update.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: update.read || muted ? readColor : defaultColor,
          decoration: muted ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        subtitleBits.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: update.read ? readColor : defaultColor,
        ),
      ),
      trailing: update.bookmark
          ? const Icon(Icons.bookmark, size: 18)
          : null,
      // While a multi-select is active, taps just toggle selection —
      // matches Mihon's behavior so the bulk action bar can be operated
      // without leaving the screen. Outside selection mode the tap
      // opens the chapter directly; long-press always enters/extends
      // selection by toggling the row, or (when not selecting) falls
      // through to the per-row action sheet.
      onTap: selecting
          ? () => onToggleSelected(update.chapterId)
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReaderScreen(
                    mangaId: update.mangaId,
                    chapterId: update.chapterId,
                  ),
                ),
              );
            },
      // Long-press always toggles selection — entering selection mode
      // when none is active. This is the natural Mihon parity behaviour
      // now that the selection bar exposes the same actions the older
      // per-row sheet covered.
      onLongPress: () => onToggleSelected(update.chapterId),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 40,
      height: 56,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book, size: 20),
    );
    if (url == null || url!.isEmpty) return fallback;
    return SizedBox(
      width: 40,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SourceImage(
          url: url!,
          fit: BoxFit.cover,
          placeholder: (_) => fallback,
          errorWidget: (_, _) => fallback,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
