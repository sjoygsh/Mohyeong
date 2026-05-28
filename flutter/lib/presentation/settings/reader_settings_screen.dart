import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        ],
      ),
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
