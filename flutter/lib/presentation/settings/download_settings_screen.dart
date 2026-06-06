import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/download/download_preferences.dart';
import 'category_filter_tile.dart';
import 'pref_tiles.dart';

/// Settings → Downloads. Mirror of Mihon's `SettingsDownloadScreen`.
///
/// Most of these are now wired: "Simultaneous downloads" (`download_slots`)
/// gates the drain loop, Wi-Fi-only gates the network check, the
/// auto-download family feeds the library updater, remove-after-read /
/// remove-after-marked-read hook the read path, CBZ is applied at finalize,
/// and "Auto download while reading" drives the reader's download-ahead.
/// Only "Split tall images" is persisted-but-unwired (no slicing pipeline).
class DownloadSettingsScreen extends ConsumerWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(downloadSlotsProvider);
    final removeSlots = ref.watch(removeAfterReadSlotsProvider);
    final downloadAhead = ref.watch(autoDownloadWhileReadingProvider);
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
          CategoryFilterTile(
            title: 'Categories to include',
            emptyLabel: 'All',
            provider: downloadNewCategoriesProvider,
          ),
          CategoryFilterTile(
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
  return 'Next $amount unread chapter${amount == 1 ? '' : 's'}';
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
