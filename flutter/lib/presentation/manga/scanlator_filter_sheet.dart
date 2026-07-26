import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/excluded_scanlators_repository.dart';
import '../tide/tide.dart';

/// Bottom sheet for excluding scanlators from a single manga's chapter
/// list. Mirrors Mihon's `ScanlatorFilterDialog`.
///
/// Tapping a row toggles it between included and excluded. When at least
/// one scanlator exists, a shortcut flips between "all included" and "all
/// excluded". Pressing Save persists the resulting set via
/// [ExcludedScanlatorsRepository.setForManga].
class ScanlatorFilterSheet extends ConsumerStatefulWidget {
  const ScanlatorFilterSheet({
    super.key,
    required this.mangaId,
    required this.availableScanlators,
    required this.initiallyExcluded,
  });

  final int mangaId;

  /// Every scanlator that has at least one chapter for this manga.
  final Set<String> availableScanlators;
  final Set<String> initiallyExcluded;

  @override
  ConsumerState<ScanlatorFilterSheet> createState() =>
      _ScanlatorFilterSheetState();
}

class _ScanlatorFilterSheetState extends ConsumerState<ScanlatorFilterSheet> {
  late final List<String> _ordered;
  late final Set<String> _excluded;

  @override
  void initState() {
    super.initState();
    _ordered = widget.availableScanlators.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _excluded = {...widget.initiallyExcluded};
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
    await ref
        .read(excludedScanlatorsRepositoryProvider)
        .setForManga(widget.mangaId, _excluded);
    if (!mounted) return;
    Navigator.of(context).pop();
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
  });

  final String name;
  final bool excluded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: 14,
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
              borderRadius: BorderRadius.circular(7),
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
        ],
      ),
    );
  }
}
