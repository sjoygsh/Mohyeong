import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/appearance_preferences.dart';
import '../theme/app_theme.dart';
import '../util/timestamp_format.dart';
import '../tide/tide.dart';
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
          _ThemeColorTile(
            current: AppColorTheme.fromKey(ref.watch(appThemeProvider)),
            onPicked: (t) => ref.read(appThemeProvider.notifier).set(t.key),
          ),
          PrefSwitch(
            title: 'Pure black',
            subtitle: 'Collapse surfaces to black on OLED screens.',
            provider: amoledProvider,
          ),
          const PrefSectionHeader('Display'),
          PrefSwitch(
            title: 'Tablet UI',
            subtitle: 'Force the two-pane layout (not yet active).',
            provider: tabletUiModeProvider,
          ),
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
          PrefSwitch(
            title: 'Render images in manga descriptions',
            subtitle: 'Not yet active.',
            provider: showImagesInDescriptionProvider,
          ),
        ],
    );
  }
}

/// "App theme" picker — swaps the colour seed that drives the whole
/// Material 3 scheme. A small swatch previews each theme's accent.
class _ThemeColorTile extends StatelessWidget {
  const _ThemeColorTile({required this.current, required this.onPicked});

  final AppColorTheme current;
  final ValueChanged<AppColorTheme> onPicked;

  @override
  Widget build(BuildContext context) {
    return PrefRow(
      icon: Icons.palette_outlined,
      title: 'App theme',
      subtitle: current.label,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Swatch(current.seed),
          const SizedBox(width: 10),
          const TideChevron(),
        ],
      ),
      onTap: () async {
        final picked = await pickPref<AppColorTheme>(
          context,
          title: 'App theme',
          selected: current,
          options: [for (final t in AppColorTheme.values) (t, t.label)],
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: TideColors.hairline),
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

