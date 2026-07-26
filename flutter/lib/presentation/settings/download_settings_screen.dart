import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/download/download_preferences.dart';
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
    return PrefScaffold(
      title: 'Downloads',
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
          PrefRow(
            icon: Icons.auto_delete_outlined,
            title: 'After reading automatically delete',
            subtitle: _removeSlotsLabel(removeSlots),
            onTap: () async {
              const options = <int>[-1, 0, 1, 2, 3, 4];
              final picked = await pickPref<int>(
                context,
                title: 'After reading automatically delete',
                selected: options.contains(removeSlots) ? removeSlots : -1,
                options: [
                  for (final v in options) (v, _removeSlotsLabel(v)),
                ],
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
          CategoryTriStateTile(
            title: 'Categories',
            message:
                'Entries in excluded categories will not be downloaded even '
                'if they are also in included categories.',
            includedProvider: downloadNewCategoriesProvider,
            excludedProvider: downloadNewCategoriesExcludeProvider,
            enabled: downloadNew,
          ),
          const PrefSectionHeader('Download ahead'),
          PrefRow(
            icon: Icons.downloading,
            title: 'Auto download while reading',
            subtitle: _downloadAheadLabel(downloadAhead),
            onTap: () async {
              // Mirrors Mihon's entries: 0 (disabled), 2, 3, 5, 10.
              const options = <int>[0, 2, 3, 5, 10];
              final picked = await pickPref<int>(
                context,
                title: 'Auto download while reading',
                selected: options.contains(downloadAhead) ? downloadAhead : 0,
                options: [
                  for (final v in options) (v, _downloadAheadLabel(v)),
                ],
              );
              if (picked != null) {
                await ref
                    .read(autoDownloadWhileReadingProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const PrefNote(
            'Only works if the current chapter and the next one are already '
            'downloaded.',
          ),
        ],
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

