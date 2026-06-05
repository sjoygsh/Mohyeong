import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_update_preference.dart';
import 'category_filter_tile.dart';

/// Library sub-screen: background update interval + display toggles.
/// Mirror of Mihon's SettingsLibraryScreen.
class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(libraryUpdatePreferenceProvider);
    final intervalNotifier =
        ref.read(libraryUpdatePreferenceProvider.notifier);
    final showCarousel = ref.watch(showMostReadCarouselProvider);
    final carouselNotifier =
        ref.read(showMostReadCarouselProvider.notifier);
    final showUnreadBadge = ref.watch(displayUnreadBadgeProvider);
    final showDownloadBadge = ref.watch(displayDownloadBadgeProvider);
    final showLocalBadge = ref.watch(displayLocalBadgeProvider);
    final showLanguageBadge = ref.watch(displayLanguageBadgeProvider);
    final showContinueReading = ref.watch(showContinueReadingButtonProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Updates',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('Update interval'),
            subtitle: Text(interval.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<LibraryUpdateInterval>(
                context: context,
                builder: (_) => _IntervalPickerDialog(current: interval),
              );
              if (picked != null) {
                await intervalNotifier.setInterval(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Global update',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          CategoryFilterTile(
            title: 'Categories to include',
            emptyLabel: 'All',
            provider: libraryUpdateCategoriesProvider,
          ),
          CategoryFilterTile(
            title: 'Categories to exclude',
            emptyLabel: 'None',
            provider: libraryUpdateCategoriesExcludeProvider,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Entries in excluded categories will not be updated even if '
              'they are also in included categories.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const _SmartUpdateSection(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Display',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            title: const Text('Show "Most read" carousel'),
            subtitle: const Text(
              'Highlights the favourites you are furthest through.',
            ),
            value: showCarousel,
            onChanged: carouselNotifier.setEnabled,
          ),
          SwitchListTile(
            title: const Text('Show continue reading button'),
            subtitle: const Text(
              'Overlay a play button on cards to resume the next '
              'unread chapter.',
            ),
            value: showContinueReading,
            onChanged: ref
                .read(showContinueReadingButtonProvider.notifier)
                .setEnabled,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Badges',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            title: const Text('Unread count'),
            subtitle: const Text(
              'Show the number of unread chapters on each card.',
            ),
            value: showUnreadBadge,
            onChanged:
                ref.read(displayUnreadBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Downloaded count'),
            subtitle: const Text(
              'Show the number of downloaded chapters on each card.',
            ),
            value: showDownloadBadge,
            onChanged:
                ref.read(displayDownloadBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Local source chip'),
            subtitle: const Text(
              'Mark cards backed by the built-in Local source.',
            ),
            value: showLocalBadge,
            onChanged:
                ref.read(displayLocalBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Language code chip'),
            subtitle: const Text(
              "Show the source's language code on each card.",
            ),
            value: showLanguageBadge,
            onChanged:
                ref.read(displayLanguageBadgeProvider.notifier).setEnabled,
          ),
        ],
      ),
    );
  }
}

/// The "Smart update" restriction checkboxes. Toggling a row adds/removes
/// its token from the [libraryUpdateMangaRestrictionProvider] set. Labels +
/// token order mirror Mihon's `SettingsLibraryScreen` multi-select.
class _SmartUpdateSection extends ConsumerWidget {
  const _SmartUpdateSection();

  static const _entries = <(String, String)>[
    (MangaUpdateRestriction.hasUnread, 'Skip entries with unread chapter(s)'),
    (MangaUpdateRestriction.nonRead, 'Skip unstarted entries'),
    (MangaUpdateRestriction.nonCompleted, 'Skip entries with "Completed" '
        'status'),
    (MangaUpdateRestriction.outsideReleasePeriod, 'Predict next release time'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryUpdateMangaRestrictionProvider);
    final notifier =
        ref.read(libraryUpdateMangaRestrictionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'Smart update',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (token, label) in _entries)
          CheckboxListTile(
            title: Text(label),
            value: selected.contains(token),
            onChanged: (checked) {
              final next = {...selected};
              if (checked ?? false) {
                next.add(token);
              } else {
                next.remove(token);
              }
              notifier.set(next);
            },
          ),
      ],
    );
  }
}

class _IntervalPickerDialog extends StatelessWidget {
  const _IntervalPickerDialog({required this.current});

  final LibraryUpdateInterval current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Update interval'),
      children: [
        RadioGroup<LibraryUpdateInterval>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in LibraryUpdateInterval.values)
                RadioListTile<LibraryUpdateInterval>(
                  value: v,
                  title: Text(v.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
