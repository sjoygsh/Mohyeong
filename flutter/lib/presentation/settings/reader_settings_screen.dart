import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';

/// Reader sub-screen: global default reading mode + visual prefs
/// (background colour, colour filter). Per-manga overrides live in
/// the reader's tune menu — these are the fallbacks.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerMode = ref.watch(readerPreferencesProvider);
    final readerNotifier = ref.read(readerPreferencesProvider.notifier);
    final background = ref.watch(readerBackgroundProvider);
    final colorFilter = ref.watch(readerColorFilterProvider);
    final autoHideSeconds = ref.watch(readerAutoHideChromeSecondsProvider);
    final doubleTapSpeed = ref.watch(readerDoubleTapAnimSpeedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'General',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('Default reading mode'),
            subtitle: Text(readerMode.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReadingMode>(
                context: context,
                builder: (_) => _ReadingModePickerDialog(current: readerMode),
              );
              if (picked != null) {
                await readerNotifier.setMode(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('Background colour'),
            subtitle: Text(background.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderBackground>(
                context: context,
                builder: (_) =>
                    _ReaderBackgroundPickerDialog(current: background),
              );
              if (picked != null) {
                await ref
                    .read(readerBackgroundProvider.notifier)
                    .set(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Colour filter'),
            subtitle: Text(colorFilter.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderColorFilter>(
                context: context,
                builder: (_) =>
                    _ReaderColorFilterPickerDialog(current: colorFilter),
              );
              if (picked != null) {
                await ref
                    .read(readerColorFilterProvider.notifier)
                    .set(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Auto-hide chrome'),
            subtitle: Text(_autoHideLabel(autoHideSeconds)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _ReaderAutoHideChromePickerDialog(current: autoHideSeconds),
              );
              if (picked != null) {
                await ref
                    .read(readerAutoHideChromeSecondsProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Behaviour',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _PrefSwitch(
            title: 'Fullscreen',
            subtitle: 'Hide the system bars while reading.',
            provider: readerFullscreenProvider,
          ),
          _PrefSwitch(
            title: 'Keep screen on',
            subtitle: 'Prevent the screen from dimming while reading.',
            provider: readerKeepScreenOnProvider,
          ),
          _PrefSwitch(
            title: 'Show page number',
            subtitle: 'Display the current / total page indicator.',
            provider: readerShowPageNumberProvider,
          ),
          _PrefSwitch(
            title: 'Show reading-mode label',
            subtitle: 'Flash the active reading mode when a chapter opens.',
            provider: readerShowReadingModeProvider,
          ),
          _PrefSwitch(
            title: 'Animate page transitions',
            subtitle: 'Slide between pages in the paged readers.',
            provider: readerPageTransitionsProvider,
          ),
          ListTile(
            title: const Text('Double-tap zoom speed'),
            subtitle: Text(_animSpeedLabel(doubleTapSpeed)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _DoubleTapSpeedPickerDialog(current: doubleTapSpeed),
              );
              if (picked != null) {
                await ref
                    .read(readerDoubleTapAnimSpeedProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Chapter navigation',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _PrefSwitch(
            title: 'Skip read chapters',
            subtitle: 'Jump past chapters already marked read.',
            provider: readerSkipReadProvider,
          ),
          _PrefSwitch(
            title: 'Skip filtered chapters',
            subtitle: "Skip chapters hidden by the manga's chapter filters.",
            provider: readerSkipFilteredProvider,
          ),
          _PrefSwitch(
            title: 'Skip duplicate chapters',
            subtitle: 'Skip chapters that repeat an adjacent chapter number.',
            provider: readerSkipDupeProvider,
          ),
          _PrefSwitch(
            title: 'Always show chapter transition',
            subtitle: 'Show the transition screen between chapters.',
            provider: readerAlwaysShowTransitionProvider,
          ),
        ],
      ),
    );
  }
}

/// Thin `SwitchListTile` wired to a bool [BoolPrefNotifier] provider.
/// Keeps the long settings list declarative.
class _PrefSwitch extends ConsumerWidget {
  const _PrefSwitch({
    required this.title,
    required this.subtitle,
    required this.provider,
  });

  final String title;
  final String subtitle;
  final NotifierProvider<BoolPrefNotifier, bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => ref.read(provider.notifier).set(v),
    );
  }
}

String _animSpeedLabel(int ms) {
  if (ms <= 0) return 'No animation';
  return '$ms ms';
}

class _DoubleTapSpeedPickerDialog extends StatelessWidget {
  const _DoubleTapSpeedPickerDialog({required this.current});

  final int current;

  static const _options = <int>[0, 250, 500];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Double-tap zoom speed'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 500,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_animSpeedLabel(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _autoHideLabel(int seconds) {
  if (seconds <= 0) return 'Off';
  return 'After $seconds second${seconds == 1 ? '' : 's'}';
}

class _ReadingModePickerDialog extends StatelessWidget {
  const _ReadingModePickerDialog({required this.current});

  final ReadingMode current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Default reading mode'),
      children: [
        RadioGroup<ReadingMode>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in ReadingMode.values)
                if (m != ReadingMode.defaultMode)
                  RadioListTile<ReadingMode>(
                    value: m,
                    title: Text(m.label),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderBackgroundPickerDialog extends StatelessWidget {
  const _ReaderBackgroundPickerDialog({required this.current});

  final ReaderBackground current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Background colour'),
      children: [
        RadioGroup<ReaderBackground>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in ReaderBackground.values)
                RadioListTile<ReaderBackground>(
                  value: b,
                  title: Text(b.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderAutoHideChromePickerDialog extends StatelessWidget {
  const _ReaderAutoHideChromePickerDialog({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Auto-hide chrome'),
      children: [
        RadioGroup<int>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in ReaderAutoHideChromeNotifier.presets)
                RadioListTile<int>(
                  value: s,
                  title: Text(_autoHideLabel(s)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderColorFilterPickerDialog extends StatelessWidget {
  const _ReaderColorFilterPickerDialog({required this.current});

  final ReaderColorFilter current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Colour filter'),
      children: [
        RadioGroup<ReaderColorFilter>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in ReaderColorFilter.values)
                RadioListTile<ReaderColorFilter>(
                  value: f,
                  title: Text(f.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
