import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_update_preference.dart';
import '../../data/preferences/theme_preference.dart';

/// Settings screen. Currently exposes appearance + library update interval.
/// More preference categories (reader, downloads, sync, ...) will live here
/// as each subsystem lands.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider);
    final themeNotifier = ref.read(themePreferenceProvider.notifier);
    final interval = ref.watch(libraryUpdatePreferenceProvider);
    final intervalNotifier =
        ref.read(libraryUpdatePreferenceProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (m) {
              if (m != null) themeNotifier.setMode(m);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('Follow system'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
          const _SectionHeader('Library'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
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
