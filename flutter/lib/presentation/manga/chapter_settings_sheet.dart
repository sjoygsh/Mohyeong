import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/base/base_preferences.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/tri_state.dart';
import '../tide/tide.dart';

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

class _ChapterSettingsSheetState extends ConsumerState<ChapterSettingsSheet> {
  int _tab = 0;
  late int _flags = widget.manga.chapterFlags;

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
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Chapters', style: TideText.display(21)),
          const SizedBox(height: 16),
          TideSegmented(
            labels: const ['Filter', 'Sort', 'Display'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 16),
          // The three panels differ in height; animating the panel rather
          // than letting it jump keeps the sheet from snapping as you move
          // between tabs.
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: tideEase,
            alignment: Alignment.topCenter,
            child: switch (_tab) {
              0 => _FilterTab(flags: _flags, onChange: _updateFlags),
              1 => _SortTab(flags: _flags, onChange: _updateFlags),
              _ => _DisplayTab(flags: _flags, onChange: _updateFlags),
            },
          ),
        ],
      ),
    );
  }
}

/// Spacing between rows in any of the three panels.
const _gap = SizedBox(height: 8);

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
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        _gap,
        _TriStateRow(
          label: 'Downloaded',
          value: downloaded,
          note: downloadedOnly ? 'Pinned by Downloaded only' : null,
          onChanged: downloadedOnly
              ? null
              : (next) => onChange(_writeTri(
                    Manga.chapterDownloadedMask,
                    Manga.chapterShowDownloaded,
                    Manga.chapterShowNotDownloaded,
                    next,
                  )),
        ),
        _gap,
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
    this.note,
  });

  final String label;
  final TriState value;

  /// Shown instead of the state word when the row is pinned, so a row you
  /// cannot move explains itself rather than just failing to respond.
  final String? note;

  /// Null renders the row disabled — used while "Downloaded only" mode
  /// pins the Downloaded axis.
  final ValueChanged<TriState>? onChanged;

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
    final (icon, state) = switch (value) {
      TriState.disabled => (Icons.check_box_outline_blank, 'Off'),
      TriState.enabledIs => (Icons.check_box, 'Include'),
      TriState.enabledNot => (Icons.disabled_by_default_outlined, 'Exclude'),
    };
    final row = TideRow(
      icon: icon,
      title: label,
      subtitle: note ?? state,
      lit: value != TriState.disabled,
      onTap: onChanged == null ? null : () => onChanged!(_next()),
    );
    // A disabled row goes quiet rather than staying at full strength and
    // silently swallowing the tap.
    return onChanged == null ? Opacity(opacity: 0.45, child: row) : row;
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
    final selected = _sortMode == mode;
    return _SortRow(
      label: label,
      selected: selected,
      descending: _descending,
      onSelect: () {
        if (selected) {
          onChange(_toggleDirection());
        } else {
          onChange(_setSortMode(mode));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row('By source', Manga.chapterSortingSource),
        _gap,
        _row('By chapter number', Manga.chapterSortingNumber),
        _gap,
        _row('By upload date', Manga.chapterSortingUploadDate),
        _gap,
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
    return TideRow(
      // The arrow only means anything on the row that is actually sorting,
      // so the others carry the neutral mark.
      icon: selected
          ? (descending ? Icons.arrow_downward : Icons.arrow_upward)
          : Icons.remove,
      title: label,
      subtitle: selected
          ? (descending ? 'Newest first' : 'Oldest first')
          : null,
      lit: selected,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TideRow(
          icon: Icons.title,
          title: 'Chapter name',
          lit: _displayMode == Manga.chapterDisplayName,
          onTap: () => onChange(_setMode(Manga.chapterDisplayName)),
        ),
        _gap,
        TideRow(
          icon: Icons.numbers,
          title: 'Chapter number',
          lit: _displayMode == Manga.chapterDisplayNumber,
          onTap: () => onChange(_setMode(Manga.chapterDisplayNumber)),
        ),
      ],
    );
  }
}
