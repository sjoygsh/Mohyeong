import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/security/security_preferences.dart';
import 'pref_tiles.dart';

/// Security sub-screen: app lock + secure screen. Mirror of Mihon's
/// `SettingsSecurityScreen`. The lock itself is enforced by `AuthGate`
/// wrapping the app's home; secure screen toggles Android `FLAG_SECURE`.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  static const _lockAfterOptions = <int, String>{
    0: 'Immediately',
    1: 'After 1 minute',
    2: 'After 2 minutes',
    5: 'After 5 minutes',
    10: 'After 10 minutes',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLock = ref.watch(appLockEnabledProvider);
    final lockAfter = ref.watch(lockAfterMinutesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          const PrefSectionHeader('App lock'),
          PrefSwitch(
            title: 'Require unlock',
            subtitle: 'Ask for biometrics or device credentials to open '
                'the app.',
            provider: appLockEnabledProvider,
          ),
          ListTile(
            enabled: appLock,
            title: const Text('Lock when idle'),
            subtitle: Text(_lockAfterOptions[lockAfter] ?? 'Immediately'),
            trailing: const Icon(Icons.chevron_right),
            onTap: appLock ? () => _pickLockAfter(context, ref) : null,
          ),
          const PrefSectionHeader('Privacy'),
          PrefSwitch(
            title: 'Secure screen',
            subtitle: 'Block screenshots and hide the app in the recent '
                'apps list.',
            provider: secureScreenProvider,
          ),
        ],
      ),
    );
  }

  Future<void> _pickLockAfter(BuildContext context, WidgetRef ref) async {
    final current = ref.read(lockAfterMinutesProvider);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lock when idle'),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _lockAfterOptions.entries)
                  RadioListTile<int>(
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(lockAfterMinutesProvider.notifier).set(picked);
    }
  }
}
