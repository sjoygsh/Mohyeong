import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';

/// Reader sub-screen: global default reading mode. Per-manga overrides
/// live in the reader's tune menu — this is the fallback when a manga
/// has no override.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerMode = ref.watch(readerPreferencesProvider);
    final readerNotifier = ref.read(readerPreferencesProvider.notifier);
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
        ],
      ),
    );
  }
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
