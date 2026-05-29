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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Update library',
            onPressed: _updating ? null : _refresh,
          ),
        ],
      ),
      body: StreamBuilder<List<LibraryUpdate>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(text: 'Failed to load updates: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final updates = snapshot.data!;
          final visible = updates.where((u) {
            if (!applyTriState(filters.unread, () => !u.read)) return false;
            if (!applyTriState(filters.bookmark, () => u.bookmark)) {
              return false;
            }
            if (filters.hideMutedScanlators && u.isScanlatorMuted) {
              return false;
            }
            return true;
          }).toList(growable: false);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: visible.isEmpty
                ? ListView(
                    // ListView so RefreshIndicator still triggers on overscroll.
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _Message(
                        text: filters.isActive
                            ? 'No updates match the current filter.'
                            : 'No new chapters.',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    itemBuilder: (context, i) =>
                        _UpdateTile(update: visible[i]),
                  ),
          );
        },
      ),
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
  const _UpdateTile({required this.update});

  final LibraryUpdate update;

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
      // Tap opens the chapter directly (Mihon parity — Updates is a
      // "what's new" feed, so the natural action is to start reading
      // it). Long-press still exposes the older details/mark-read
      // actions via a bottom sheet.
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              mangaId: update.mangaId,
              chapterId: update.chapterId,
            ),
          ),
        );
      },
      onLongPress: () => _showRowMenu(context, ref),
    );
  }

  Future<void> _showRowMenu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_UpdateRowAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Open manga details'),
              onTap: () => Navigator.of(ctx).pop(_UpdateRowAction.openDetails),
            ),
            ListTile(
              leading: Icon(
                update.read
                    ? Icons.radio_button_unchecked
                    : Icons.check_circle_outline,
              ),
              title: Text(update.read ? 'Mark as unread' : 'Mark as read'),
              onTap: () => Navigator.of(ctx).pop(_UpdateRowAction.toggleRead),
            ),
            ListTile(
              leading: Icon(
                update.bookmark
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              title:
                  Text(update.bookmark ? 'Remove bookmark' : 'Add bookmark'),
              onTap: () => Navigator.of(ctx).pop(_UpdateRowAction.toggleBookmark),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (!context.mounted) return;
    final repo = ref.read(chapterRepositoryProvider);
    switch (action) {
      case _UpdateRowAction.openDetails:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(mangaId: update.mangaId),
          ),
        );
      case _UpdateRowAction.toggleRead:
        await repo.setRead(update.chapterId, !update.read);
      case _UpdateRowAction.toggleBookmark:
        await repo.setBookmark(update.chapterId, !update.bookmark);
    }
  }
}

enum _UpdateRowAction { openDetails, toggleRead, toggleBookmark }

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
