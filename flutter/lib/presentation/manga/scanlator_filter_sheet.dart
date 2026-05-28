import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/excluded_scanlators_repository.dart';

/// Bottom sheet for excluding scanlators from a single manga's chapter
/// list. Mirrors Mihon's `ScanlatorFilterDialog`.
///
/// Tapping a row toggles it between included (empty box icon) and
/// excluded (cross-out icon). When at least one scanlator exists, the
/// header row shows a Select-all / Reset shortcut that flips between
/// "all included" and "all excluded" states. Pressing Save persists the
/// resulting set via [ExcludedScanlatorsRepository.setForManga].
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
                'Exclude scanlators',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_ordered.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child:
                    Text('No scanlators found in this manga\'s chapter list.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _ordered.length,
                  itemBuilder: (_, i) {
                    final name = _ordered[i];
                    final excluded = _excluded.contains(name);
                    return ListTile(
                      leading: Icon(
                        excluded
                            ? Icons.disabled_by_default
                            : Icons.check_box_outline_blank,
                        color: excluded
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(name),
                      onTap: () => _toggle(name),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  if (_ordered.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        if (_excluded.isEmpty) {
                          _excluded.addAll(_ordered);
                        } else {
                          _excluded.clear();
                        }
                      }),
                      child: Text(
                        _excluded.isEmpty ? 'Exclude all' : 'Reset',
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _ordered.isEmpty ? null : _save,
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
