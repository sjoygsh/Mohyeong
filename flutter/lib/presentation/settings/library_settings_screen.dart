import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_update_preference.dart';

/// Library sub-screen: background update interval. Mirror of Mihon's
/// SettingsLibraryScreen.
class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(libraryUpdatePreferenceProvider);
    final intervalNotifier =
        ref.read(libraryUpdatePreferenceProvider.notifier);
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
