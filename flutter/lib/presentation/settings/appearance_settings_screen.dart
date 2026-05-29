import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/appearance_preferences.dart';
import '../../data/preferences/theme_preference.dart';
import 'pref_tiles.dart';

/// Appearance sub-screen: theme mode, AMOLED dark, and display
/// preferences. Mirror of Mihon's `SettingsAppearanceScreen`.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider);
    final themeNotifier = ref.read(themePreferenceProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          const PrefSectionHeader('Theme'),
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
          PrefSwitch(
            title: 'AMOLED black',
            subtitle: 'Use a pure-black background in dark mode.',
            provider: amoledProvider,
          ),
          const PrefSectionHeader('Timestamps'),
          PrefSwitch(
            title: 'Relative timestamps',
            subtitle: 'Show times as "2h ago" (not yet active).',
            provider: relativeTimestampsProvider,
          ),
          const PrefSectionHeader('Display'),
          PrefSwitch(
            title: 'Tablet UI',
            subtitle: 'Force the two-pane layout (not yet active).',
            provider: tabletUiModeProvider,
          ),
          PrefSwitch(
            title: 'Images in description',
            subtitle: 'Render images embedded in manga descriptions '
                '(not yet active).',
            provider: showImagesInDescriptionProvider,
          ),
        ],
      ),
    );
  }
}
