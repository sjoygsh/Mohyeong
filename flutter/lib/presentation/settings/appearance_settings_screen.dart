import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/appearance_preferences.dart';
import '../../data/preferences/theme_preference.dart';
import '../util/timestamp_format.dart';
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
            subtitle: 'Show history times as "2h ago" instead of dates.',
            provider: relativeTimestampsProvider,
          ),
          _DateFormatTile(
            current: ref.watch(dateFormatProvider),
            onPicked: (pattern) =>
                ref.read(dateFormatProvider.notifier).set(pattern),
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

/// Mihon's `DateFormats` presets — an empty pattern means "device default"
/// (locale-aware short date). Each is previewed against the current date.
const List<String> _dateFormatPatterns = [
  '',
  'MM/dd/yy',
  'dd/MM/yy',
  'yyyy-MM-dd',
  'dd MMM yyyy',
  'MMM dd, yyyy',
];

String _dateFormatLabel(String pattern) {
  final preview = formatDate(DateTime.now(), pattern);
  return pattern.isEmpty ? 'Default ($preview)' : '$pattern ($preview)';
}

class _DateFormatTile extends StatelessWidget {
  const _DateFormatTile({required this.current, required this.onPicked});

  final String current;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Date format'),
      subtitle: Text(_dateFormatLabel(current)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => _DateFormatPickerDialog(current: current),
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

class _DateFormatPickerDialog extends StatelessWidget {
  const _DateFormatPickerDialog({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final groupValue =
        _dateFormatPatterns.contains(current) ? current : '';
    return SimpleDialog(
      title: const Text('Date format'),
      children: [
        RadioGroup<String>(
          groupValue: groupValue,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in _dateFormatPatterns)
                RadioListTile<String>(
                  value: p,
                  title: Text(_dateFormatLabel(p)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
