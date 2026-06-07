import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/download/download_preferences.dart';
import '../../domain/category/model/category.dart';
import 'category_filter_tile.dart';
import 'pref_tiles.dart';

/// Settings → Downloads. Mirror of Mihon's `SettingsDownloadScreen`.
///
/// Top-level items (no header) cover Wi-Fi-only, CBZ, split-tall and the two
/// concurrency sliders, followed by the "Delete chapters", "Auto-download"
/// and "Download ahead" groups. Almost everything is wired: the sliders feed
/// the queue's chapter/page concurrency, Wi-Fi-only gates the drain, the
/// auto-download family feeds the library updater, the remove-after-read
/// family (incl. excluded categories) hooks the read path, CBZ is applied at
/// finalize, and download-ahead drives the reader. Only "Split tall images"
/// is persisted-but-unwired (no slicing pipeline).
class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceLimit = ref.watch(parallelSourceLimitProvider);
    final pageLimit = ref.watch(parallelPageLimitProvider);
    final removeSlots = ref.watch(removeAfterReadSlotsProvider);
    final downloadAhead = ref.watch(autoDownloadWhileReadingProvider);
    final downloadNew = ref.watch(downloadNewChaptersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListView(
        children: [
          PrefSwitch(
            title: 'Only on Wi-Fi',
            provider: downloadOnlyOverWifiProvider,
          ),
          PrefSwitch(
            title: 'Save as CBZ archive',
            provider: saveChaptersAsCbzProvider,
          ),
          PrefSwitch(
            title: 'Split tall images',
            subtitle: 'Improves reader performance',
            provider: splitTallImagesProvider,
          ),
          PrefSlider(
            title: 'Concurrent source downloads',
            value: sourceLimit,
            min: 1,
            max: 10,
            onChanged: (v) =>
                ref.read(parallelSourceLimitProvider.notifier).set(v),
          ),
          PrefSlider(
            title: 'Concurrent page downloads',
            subtitle: 'Pages downloaded simultaneously per source',
            value: pageLimit,
            min: 1,
            max: 15,
            onChanged: (v) =>
                ref.read(parallelPageLimitProvider.notifier).set(v),
          ),
          const PrefSectionHeader('Delete chapters'),
          PrefSwitch(
            title: 'After manually marked as read',
            provider: removeAfterMarkedAsReadProvider,
          ),
          ListTile(
            title: const Text('After reading automatically delete'),
            subtitle: Text(_removeSlotsLabel(removeSlots)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) => _RemoveSlotsPickerDialog(current: removeSlots),
              );
              if (picked != null) {
                await ref
                    .read(removeAfterReadSlotsProvider.notifier)
                    .set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Allow deleting bookmarked chapters',
            provider: removeBookmarkedChaptersProvider,
          ),
          CategoryFilterTile(
            title: 'Excluded categories',
            emptyLabel: 'None',
            provider: removeExcludeCategoriesProvider,
          ),
          const PrefSectionHeader('Auto-download'),
          PrefSwitch(
            title: 'Download new chapters',
            provider: downloadNewChaptersProvider,
          ),
          PrefSwitch(
            title: 'Skip downloading duplicate read chapters',
            provider: downloadNewUnreadChaptersOnlyProvider,
            enabled: downloadNew,
          ),
          _AutoDownloadCategoriesTile(enabled: downloadNew),
          const PrefSectionHeader('Download ahead'),
          ListTile(
            title: const Text('Auto download while reading'),
            subtitle: Text(_downloadAheadLabel(downloadAhead)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _DownloadAheadPickerDialog(current: downloadAhead),
              );
              if (picked != null) {
                await ref
                    .read(autoDownloadWhileReadingProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Only works if the current chapter + the next one are already '
              'downloaded.',
            ),
          ),
        ],
      ),
    );
  }
}

String _downloadAheadLabel(int amount) {
  if (amount == 0) return 'Disabled';
  return amount == 1
      ? 'Next unread chapter'
      : 'Next $amount unread chapters';
}

/// Subtitle/option text for `removeAfterReadSlots`, matching Mihon's entries:
/// -1 disabled, 0 last-read, then second…fifth to last read chapter.
String _removeSlotsLabel(int slots) {
  return switch (slots) {
    0 => 'Last read chapter',
    1 => 'Second to last read chapter',
    2 => 'Third to last read chapter',
    3 => 'Fourth to last read chapter',
    4 => 'Fifth to last read chapter',
    _ => 'Disabled',
  };
}

/// The auto-download "Categories" tri-state tile: each category is neutral,
/// included, or excluded. Mirrors Mihon's `TriStateListDialog` + the
/// `getCategoriesLabel` subtitle ("Include: …\nExclude: …").
class _AutoDownloadCategoriesTile extends ConsumerWidget {
  const _AutoDownloadCategoriesTile({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final included = ref.watch(downloadNewCategoriesProvider);
    final excluded = ref.watch(downloadNewCategoriesExcludeProvider);
    final categories =
        ref.watch(userCategoriesProvider).valueOrNull ?? const <Category>[];
    return ListTile(
      title: const Text('Categories'),
      subtitle: Text(_categoriesLabel(categories, included, excluded)),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled && categories.isNotEmpty,
      onTap: () async {
        final result = await showDialog<_TriStateResult>(
          context: context,
          builder: (_) => _TriStateCategoryDialog(
            categories: categories,
            included: included,
            excluded: excluded,
          ),
        );
        if (result != null) {
          await ref
              .read(downloadNewCategoriesProvider.notifier)
              .set(result.included);
          await ref
              .read(downloadNewCategoriesExcludeProvider.notifier)
              .set(result.excluded);
        }
      },
    );
  }
}

String _categoriesLabel(
  List<Category> all,
  Set<String> included,
  Set<String> excluded,
) {
  final inc =
      all.where((c) => included.contains(c.id.toString())).toList();
  final exc =
      all.where((c) => excluded.contains(c.id.toString())).toList();
  final allExcluded = all.isNotEmpty && exc.length == all.length;

  final String incText;
  if (inc.isNotEmpty && inc.length != all.length) {
    incText = inc.map((c) => c.name).join(', ');
  } else if (all.isNotEmpty && inc.length == all.length) {
    incText = 'All';
  } else if (allExcluded) {
    incText = 'None';
  } else {
    incText = 'All';
  }

  final String excText;
  if (exc.isEmpty) {
    excText = 'None';
  } else if (allExcluded) {
    excText = 'All';
  } else {
    excText = exc.map((c) => c.name).join(', ');
  }

  return 'Include: $incText\nExclude: $excText';
}

class _TriStateResult {
  const _TriStateResult(this.included, this.excluded);
  final Set<String> included;
  final Set<String> excluded;
}

class _TriStateCategoryDialog extends StatefulWidget {
  const _TriStateCategoryDialog({
    required this.categories,
    required this.included,
    required this.excluded,
  });

  final List<Category> categories;
  final Set<String> included;
  final Set<String> excluded;

  @override
  State<_TriStateCategoryDialog> createState() =>
      _TriStateCategoryDialogState();
}

class _TriStateCategoryDialogState extends State<_TriStateCategoryDialog> {
  late final Set<String> _included = {...widget.included};
  late final Set<String> _excluded = {...widget.excluded};

  // neutral -> include -> exclude -> neutral
  void _cycle(String id) {
    setState(() {
      if (_included.contains(id)) {
        _included.remove(id);
        _excluded.add(id);
      } else if (_excluded.contains(id)) {
        _excluded.remove(id);
      } else {
        _included.add(id);
      }
    });
  }

  IconData _iconFor(String id) {
    if (_included.contains(id)) return Icons.check_box;
    if (_excluded.contains(id)) return Icons.indeterminate_check_box;
    return Icons.check_box_outline_blank;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Entries in excluded categories will not be downloaded even '
                'if they are also in included categories.',
              ),
            ),
            for (final c in widget.categories)
              ListTile(
                leading: Icon(_iconFor(c.id.toString())),
                title: Text(c.name),
                onTap: () => _cycle(c.id.toString()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _TriStateResult(_included, _excluded),
          ),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _DownloadAheadPickerDialog extends StatelessWidget {
  const _DownloadAheadPickerDialog({required this.current});

  final int current;

  // Mirrors Mihon's entries: 0 (disabled), 2, 3, 5, 10.
  static const _options = <int>[0, 2, 3, 5, 10];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Auto download while reading'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 0,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_downloadAheadLabel(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RemoveSlotsPickerDialog extends StatelessWidget {
  const _RemoveSlotsPickerDialog({required this.current});

  final int current;

  // Mirrors Mihon's removeAfterReadSlots entries: -1, 0, 1, 2, 3, 4.
  static const _options = <int>[-1, 0, 1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('After reading automatically delete'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : -1,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_removeSlotsLabel(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
