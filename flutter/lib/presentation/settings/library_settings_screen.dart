import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_update_preference.dart';

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
