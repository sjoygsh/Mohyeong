import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/base/base_preferences.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';

/// Chapter settings bottom-sheet — filter / sort / display picker for the
/// per-manga `chapter_flags` bitmask. Mirrors Mihon's
/// `ChapterSettingsDialog` (Filter / Sort / Display tabs).
///
/// All three sections read and write the same `chapter_flags` integer
/// using the bit constants on the [Manga] class so values persist exactly
/// where the Kotlin app stored them. Edits write back through
/// [MangaRepository.setChapterFlags].
class ChapterSettingsSheet extends ConsumerStatefulWidget {
  const ChapterSettingsSheet({super.key, required this.manga});

  final Manga manga;

  @override
  ConsumerState<ChapterSettingsSheet> createState() =>
      _ChapterSettingsSheetState();
}

class _ChapterSettingsSheetState extends ConsumerState<ChapterSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late int _flags = widget.manga.chapterFlags;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_flags == widget.manga.chapterFlags) return;
    await ref
        .read(mangaRepositoryProvider)
        .setChapterFlags(widget.manga.id, _flags);
  }

  void _updateFlags(int next) {
    setState(() => _flags = next);
    // Persist immediately — Mihon's sheet auto-saves on every toggle.
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Filter'),
                Tab(text: 'Sort'),
                Tab(text: 'Display'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _FilterTab(flags: _flags, onChange: _updateFlags),
                  _SortTab(flags: _flags, onChange: _updateFlags),
                  _DisplayTab(flags: _flags, onChange: _updateFlags),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTab extends ConsumerWidget {
  const _FilterTab({required this.flags, required this.onChange});

  final int flags;
  final ValueChanged<int> onChange;

  TriState _readTri(int mask, int isFlag, int notFlag) {
    final v = flags & mask;
    if (v == isFlag) return TriState.enabledIs;
    if (v == notFlag) return TriState.enabledNot;
    return TriState.disabled;
  }

  int _writeTri(int mask, int isFlag, int notFlag, TriState next) {
    final cleared = flags & ~mask;
    switch (next) {
      case TriState.disabled:
        return cleared;
      case TriState.enabledIs:
        return cleared | isFlag;
      case TriState.enabledNot:
        return cleared | notFlag;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "Downloaded only" mode pins the Downloaded axis (Kotlin
    // ChapterSettingsDialog: onClick null while downloadedOnly).
    final downloadedOnly = ref.watch(downloadedOnlyProvider);
    final unread = _readTri(
      Manga.chapterUnreadMask,
      Manga.chapterShowUnread,
      Manga.chapterShowRead,
    );
    final downloaded = downloadedOnly
        ? TriState.enabledIs
        : _readTri(
            Manga.chapterDownloadedMask,
            Manga.chapterShowDownloaded,
            Manga.chapterShowNotDownloaded,
          );
    final bookmarked = _readTri(
      Manga.chapterBookmarkedMask,
      Manga.chapterShowBookmarked,
      Manga.chapterShowNotBookmarked,
    );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _TriStateRow(
          label: 'Unread',
          value: unread,
          onChanged: (next) => onChange(_writeTri(
            Manga.chapterUnreadMask,
            Manga.chapterShowUnread,
            Manga.chapterShowRead,
            next,
          )),
        ),
        _TriStateRow(
          label: 'Downloaded',
          value: downloaded,
          onChanged: downloadedOnly
              ? null
              : (next) => onChange(_writeTri(
                    Manga.chapterDownloadedMask,
                    Manga.chapterShowDownloaded,
                    Manga.chapterShowNotDownloaded,
                    next,
                  )),
        ),
        _TriStateRow(
          label: 'Bookmarked',
          value: bookmarked,
          onChanged: (next) => onChange(_writeTri(
            Manga.chapterBookmarkedMask,
            Manga.chapterShowBookmarked,
            Manga.chapterShowNotBookmarked,
            next,
          )),
        ),
      ],
    );
  }
}

class _TriStateRow extends StatelessWidget {
  const _TriStateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TriState value;

  /// Null renders the row disabled — used while "Downloaded only" mode
  /// pins the Downloaded axis.
  final ValueChanged<TriState>? onChanged;

  IconData _icon() {
    switch (value) {
      case TriState.disabled:
        return Icons.check_box_outline_blank;
      case TriState.enabledIs:
        return Icons.check_box;
      case TriState.enabledNot:
        return Icons.indeterminate_check_box;
    }
  }

  TriState _next() {
    switch (value) {
      case TriState.disabled:
        return TriState.enabledIs;
      case TriState.enabledIs:
        return TriState.enabledNot;
      case TriState.enabledNot:
        return TriState.disabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onChanged != null,
      leading: Icon(_icon()),
      title: Text(label),
      onTap: onChanged == null ? null : () => onChanged!(_next()),
    );
  }
}

class _SortTab extends StatelessWidget {
  const _SortTab({required this.flags, required this.onChange});

  final int flags;
  final ValueChanged<int> onChange;

  int get _sortMode => flags & Manga.chapterSortingMask;
  bool get _descending =>
      (flags & Manga.chapterSortDirMask) == Manga.chapterSortDesc;

  int _setSortMode(int newMode) {
    return (flags & ~Manga.chapterSortingMask) | newMode;
  }

  int _toggleDirection() {
    return _descending
        ? ((flags & ~Manga.chapterSortDirMask) | Manga.chapterSortAsc)
        : ((flags & ~Manga.chapterSortDirMask) | Manga.chapterSortDesc);
  }

  Widget _row(String label, int mode) {
    return _SortRow(
      label: label,
      selected: _sortMode == mode,
      descending: _descending,
      onSelect: () {
        if (_sortMode == mode) {
          onChange(_toggleDirection());
        } else {
          onChange(_setSortMode(mode));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _row('By source', Manga.chapterSortingSource),
        _row('By chapter number', Manga.chapterSortingNumber),
        _row('By upload date', Manga.chapterSortingUploadDate),
        _row('Alphabetically', Manga.chapterSortingAlphabet),
      ],
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.label,
    required this.selected,
    required this.descending,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final bool descending;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: selected
          ? Icon(descending ? Icons.arrow_downward : Icons.arrow_upward)
          : const SizedBox(width: 24),
      title: Text(label),
      onTap: onSelect,
    );
  }
}

class _DisplayTab extends StatelessWidget {
  const _DisplayTab({required this.flags, required this.onChange});

  final int flags;
  final ValueChanged<int> onChange;

  int get _displayMode => flags & Manga.chapterDisplayMask;

  int _setMode(int newMode) {
    return (flags & ~Manga.chapterDisplayMask) | newMode;
  }

  @override
  Widget build(BuildContext context) {
    return RadioGroup<int>(
      groupValue: _displayMode,
      onChanged: (v) {
        if (v != null) onChange(_setMode(v));
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          RadioListTile<int>(
            title: Text('Chapter name'),
            value: Manga.chapterDisplayName,
          ),
          RadioListTile<int>(
            title: Text('Chapter number'),
            value: Manga.chapterDisplayNumber,
          ),
        ],
      ),
    );
  }
}
