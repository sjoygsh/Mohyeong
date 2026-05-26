import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/theme_preference.dart';

/// First Settings sub-screen: theme mode. More preference categories
/// (library, reader, downloads, sync, ...) will live alongside this as
/// each subsystem lands.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themePreferenceProvider);
    final notifier = ref.read(themePreferenceProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (m) {
          if (m != null) notifier.setMode(m);
        },
        child: ListView(
          children: const [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Appearance',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
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
    );
  }
}
