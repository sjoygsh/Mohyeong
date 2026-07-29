import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/appearance_preferences.dart';
import '../util/timestamp_format.dart';
import 'pref_tiles.dart';

/// Appearance sub-screen: theme mode, AMOLED dark, and display
/// preferences. Mirror of Mihon's `SettingsAppearanceScreen`.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datePattern = ref.watch(dateFormatProvider);
    return PrefScaffold(
      title: 'Appearance',
      children: [
          const PrefSectionHeader('Theme'),
          PrefSwitch(
            title: 'Pure black',
            subtitle: 'Collapse surfaces to black on OLED screens.',
            provider: amoledProvider,
          ),
          const PrefSectionHeader('Display'),
          _DateFormatTile(
            current: datePattern,
            onPicked: (pattern) =>
                ref.read(dateFormatProvider.notifier).set(pattern),
          ),
          PrefSwitch(
            title: 'Relative timestamps',
            subtitle:
                '"Today" instead of "${formatDate(DateTime.now(), datePattern)}"',
            provider: relativeTimestampsProvider,
          ),
        ],
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
    return PrefRow(
      icon: Icons.event_outlined,
      title: 'Date format',
      subtitle: _dateFormatLabel(current),
      onTap: () async {
        final picked = await pickPref<String>(
          context,
          title: 'Date format',
          selected: _dateFormatPatterns.contains(current) ? current : '',
          options: [
            for (final p in _dateFormatPatterns) (p, _dateFormatLabel(p)),
          ],
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

