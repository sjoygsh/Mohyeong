import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/category/category_repository.dart';
import '../../data/download/download_preferences.dart';
import '../../data/preferences/typed_preferences.dart';
import '../../domain/category/model/category.dart';
import 'pref_tiles.dart';

/// User categories for the auto-download include/exclude pickers. System
/// categories (the "Uncategorized" bucket) are filtered out — Mihon's
/// include/exclude lists operate on user-defined categories only.
final _userCategoriesProvider = StreamProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll().map(
        (cats) => cats.where((c) => !c.isSystemCategory).toList(),
      ),
);

/// Settings → Downloads. Mirror of Mihon's `SettingsDownloadScreen`.
///
/// Of these, only "Simultaneous downloads" is consumed today — the
/// download queue reads `download_slots` at drain time. The rest are
/// persisted (keys mirror Mihon) and surfaced here, but their behaviour
/// is not yet implemented (no connectivity plugin for Wi-Fi-only, no
/// archive pipeline for CBZ/split-tall, and no updater/read hooks for
/// auto-download / remove-after-read).
class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(downloadSlotsProvider);
    final removeSlots = ref.watch(removeAfterReadSlotsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListView(
        children: [
          const PrefSectionHeader('General'),
          ListTile(
            title: const Text('Simultaneous downloads'),
            subtitle: Text('$slots at a time'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) => _SlotsPickerDialog(current: slots),
              );
              if (picked != null) {
                await ref.read(downloadSlotsProvider.notifier).set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Only download over Wi-Fi',
            subtitle: 'Pause downloads on metered connections.',
            provider: downloadOnlyOverWifiProvider,
          ),
          const PrefSectionHeader('Auto-download'),
          PrefSwitch(
            title: 'Download new chapters',
            subtitle: 'Fetch new chapters automatically after a library '
                'update.',
            provider: downloadNewChaptersProvider,
          ),
          PrefSwitch(
            title: 'Download new unread chapters only',
            subtitle: "Skip chapters whose number you've already read.",
            provider: downloadNewUnreadChaptersOnlyProvider,
          ),
          _CategoryFilterTile(
            title: 'Categories to include',
            emptyLabel: 'All',
            provider: downloadNewCategoriesProvider,
          ),
          _CategoryFilterTile(
            title: 'Categories to exclude',
            emptyLabel: 'None',
            provider: downloadNewCategoriesExcludeProvider,
          ),
          const PrefSectionHeader('Auto-remove'),
          PrefSwitch(
            title: 'Remove after marked as read',
            subtitle: 'Delete a chapter download once you mark it read.',
            provider: removeAfterMarkedAsReadProvider,
          ),
          ListTile(
            title: const Text('Keep read chapters'),
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
            title: 'Exclude bookmarked chapters',
            subtitle: "Don't auto-remove chapters you've bookmarked.",
            provider: removeBookmarkedChaptersProvider,
          ),
          const PrefSectionHeader('Storage format'),
          PrefSwitch(
            title: 'Save chapters as CBZ',
            subtitle: 'Archive each chapter into a single CBZ file.',
            provider: saveChaptersAsCbzProvider,
          ),
          PrefSwitch(
            title: 'Split tall images',
            subtitle: 'Slice long strip images into screen-height pages.',
            provider: splitTallImagesProvider,
          ),
        ],
      ),
    );
  }
}

String _removeSlotsLabel(int slots) {
  if (slots < 0) return 'Keep all read chapters';
  if (slots == 0) return 'Remove as soon as read';
  return 'Keep the last $slots chapter${slots == 1 ? '' : 's'}';
}

class _SlotsPickerDialog extends StatelessWidget {
  const _SlotsPickerDialog({required this.current});

  final int current;

  static const _options = <int>[1, 2, 3, 4, 5];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Simultaneous downloads'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 1,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text('$v'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tile + dialog for an auto-download category include/exclude set. The
/// stored value is a [Set] of category-id strings (Mihon-compatible). The
/// subtitle renders the selected category names, or [emptyLabel] when the
/// set is empty.
class _CategoryFilterTile extends ConsumerWidget {
  const _CategoryFilterTile({
    required this.title,
    required this.emptyLabel,
    required this.provider,
  });

  final String title;
  final String emptyLabel;
  final NotifierProvider<StringSetPrefNotifier, Set<String>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(provider);
    final categoriesAsync = ref.watch(_userCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];

    String subtitle;
    if (selected.isEmpty) {
      subtitle = emptyLabel;
    } else {
      final names = categories
          .where((c) => selected.contains(c.id.toString()))
          .map((c) => c.name)
          .toList();
      subtitle = names.isEmpty ? emptyLabel : names.join(', ');
    }

    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      enabled: categories.isNotEmpty,
      onTap: () async {
        final picked = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _CategoryFilterDialog(
            title: title,
            categories: categories,
            initial: selected,
          ),
        );
        if (picked != null) {
          await ref.read(provider.notifier).set(picked);
        }
      },
    );
  }
}

class _CategoryFilterDialog extends StatefulWidget {
  const _CategoryFilterDialog({
    required this.title,
    required this.categories,
    required this.initial,
  });

  final String title;
  final List<Category> categories;
  final Set<String> initial;

  @override
  State<_CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<_CategoryFilterDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in widget.categories)
              CheckboxListTile(
                title: Text(c.name),
                value: _selected.contains(c.id.toString()),
                onChanged: (checked) => setState(() {
                  final key = c.id.toString();
                  if (checked ?? false) {
                    _selected.add(key);
                  } else {
                    _selected.remove(key);
                  }
                }),
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _RemoveSlotsPickerDialog extends StatelessWidget {
  const _RemoveSlotsPickerDialog({required this.current});

  final int current;

  static const _options = <int>[-1, 0, 1, 2, 5];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Keep read chapters'),
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
