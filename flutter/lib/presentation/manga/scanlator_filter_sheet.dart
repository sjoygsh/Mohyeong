import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/excluded_scanlators_repository.dart';
import '../../data/manga/scanlator_priority_repository.dart';
import '../tide/tide.dart';

/// Bottom sheet for excluding and ranking the scanlators on a single manga's
/// chapter list. Mirrors Mihon's `ScanlatorFilterDialog`.
///
/// Tapping a row toggles it between included and excluded. When at least
/// one scanlator exists, a shortcut flips between "all included" and "all
/// excluded". The arrows reorder: when several scanlators publish the same
/// chapter number, only the highest one in this list is shown. Pressing Save
/// persists the set via [ExcludedScanlatorsRepository.setForManga] and the
/// order via [ScanlatorPriorityRepository.setForManga] — same as the fork,
/// which writes both from one OK button.
class ScanlatorFilterSheet extends ConsumerStatefulWidget {
  const ScanlatorFilterSheet({
    super.key,
    required this.mangaId,
    required this.availableScanlators,
    required this.initiallyExcluded,
    this.initialPriority = const [],
  });

  final int mangaId;

  /// Every scanlator that has at least one chapter for this manga.
  final Set<String> availableScanlators;
  final Set<String> initiallyExcluded;

  /// Stored ranking, most preferred first. Names no longer present in
  /// [availableScanlators] are dropped.
  final List<String> initialPriority;

  @override
  ConsumerState<ScanlatorFilterSheet> createState() =>
      _ScanlatorFilterSheetState();
}

class _ScanlatorFilterSheetState extends ConsumerState<ScanlatorFilterSheet> {
  late final List<String> _ordered;
  late final Set<String> _excluded;

  /// True once this manga has a ranking worth storing — either one was
  /// already stored, or the user moved a row in this sheet.
  late bool _reordered;

  @override
  void initState() {
    super.initState();
    // Ranked names first, in their stored order, then everything unranked
    // alphabetically — 1:1 with the fork's head/tail construction. A stored
    // name whose chapters are gone is dropped rather than shown as a ghost.
    final ranked = [
      for (final name in widget.initialPriority)
        if (widget.availableScanlators.contains(name)) name,
    ];
    final seen = ranked.toSet();
    final rest = [
      for (final name in widget.availableScanlators)
        if (!seen.contains(name)) name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _ordered = [...ranked, ...rest];
    _excluded = {...widget.initiallyExcluded};
    _reordered = ranked.isNotEmpty;
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _ordered.length) return;
    setState(() {
      _reordered = true;
      final moved = _ordered[index];
      _ordered[index] = _ordered[target];
      _ordered[target] = moved;
    });
  }

  void _toggle(String name) {
    setState(() {
      if (_excluded.contains(name)) {
        _excluded.remove(name);
      } else {
        _excluded.add(name);
      }
    });
  }

  Future<void> _save() async {
    final nav = Navigator.of(context);
    await ref
        .read(excludedScanlatorsRepositoryProvider)
        .setForManga(widget.mangaId, _excluded);
    // Only persist an order once the user has actually expressed one; writing
    // the default alphabetical list would silently start collapsing duplicate
    // chapter numbers for a manga nobody ranked.
    if (_reordered) {
      await ref
          .read(scanlatorPriorityRepositoryProvider)
          .setForManga(widget.mangaId, _ordered);
    }
    if (!mounted) return;
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final showing = _ordered.length - _excluded.length;
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Scanlators', style: TideText.display(21)),
          const SizedBox(height: 6),
          Text(
            _ordered.isEmpty
                ? 'No scanlators are credited on this series.'
                : '$showing of ${_ordered.length} showing',
            style: TideText.caption(size: 13),
          ),
          if (_ordered.isNotEmpty) ...[
            const SizedBox(height: 18),
            // The list is bounded so a series with forty scanlators scrolls
            // inside the panel instead of growing the panel past the screen.
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _ordered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (_, i) {
                  final name = _ordered[i];
                  return _ScanlatorRow(
                    name: name,
                    excluded: _excluded.contains(name),
                    onTap: () => _toggle(name),
                    // Reordering only means anything when something can lose
                    // a chapter number to something else.
                    onMoveUp:
                        _ordered.length > 1 && i > 0 ? () => _move(i, -1) : null,
                    onMoveDown: _ordered.length > 1 && i < _ordered.length - 1
                        ? () => _move(i, 1)
                        : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (_excluded.isEmpty) {
                  _excluded.addAll(_ordered);
                } else {
                  _excluded.clear();
                }
              }),
              child: Text(
                _excluded.isEmpty ? 'Hide all' : 'Show all',
                style: TideText.title(size: 13, color: TideColors.accent),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              if (_ordered.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: TideButton(
                    label: 'Save',
                    primary: true,
                    onTap: _save,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One scanlator. Excluded reads as struck through and dimmed, so the state
/// is legible from the text alone — the marker on the left only confirms it.
class _ScanlatorRow extends StatelessWidget {
  const _ScanlatorRow({
    required this.name,
    required this.excluded,
    required this.onTap,
    this.onMoveUp,
    this.onMoveDown,
  });

  final String name;
  final bool excluded;
  final VoidCallback onTap;

  /// Null at the ends of the list, which disables the arrow rather than
  /// hiding it so the rows keep a single shape.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: TideRadius.row,
      tintTop: excluded ? 0.04 : 0.085,
      tintBottom: excluded ? 0.015 : 0.03,
      highlight: excluded ? 0.07 : 0.15,
      border: excluded ? 0.06 : 0.10,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: tideEase,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: excluded
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(TideRadius.tag),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: excluded ? 0.13 : 0.26),
              ),
            ),
            child: excluded
                ? null
                : Icon(Icons.check_rounded,
                    size: 13, color: TideColors.textAt(0.8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TideText.title(
                size: 14,
                color: TideColors.textAt(excluded ? 0.3 : 0.88),
              ).copyWith(
                decoration: excluded ? TextDecoration.lineThrough : null,
                decorationColor: TideColors.textAt(0.3),
              ),
            ),
          ),
          if (onMoveUp != null || onMoveDown != null) ...[
            _MoveArrow(icon: Icons.keyboard_arrow_up, onTap: onMoveUp),
            _MoveArrow(icon: Icons.keyboard_arrow_down, onTap: onMoveDown),
          ],
        ],
      ),
    );
  }
}

/// One reorder arrow. Dimmed and inert at the ends of the list.
class _MoveArrow extends StatelessWidget {
  const _MoveArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(
          icon,
          size: 20,
          color: TideColors.textAt(onTap == null ? 0.16 : 0.6),
        ),
      ),
    );
  }
}
