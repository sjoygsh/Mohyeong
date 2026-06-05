import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/security/security_preferences.dart';
import 'pref_tiles.dart';

/// Security sub-screen: app lock + secure screen + notification privacy.
/// Mirror of Mihon's `SettingsSecurityScreen`. The lock itself is enforced by
/// `AuthGate` wrapping the app's home (biometric / device-credential prompt on
/// cold start and after the idle timeout); the secure-screen mode drives the
/// Android `FLAG_SECURE` window flag.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  /// Idle-timeout options. Keys are Mihon's `lock_app_after` minute values:
  /// -1 = never, 0 = immediately. The remaining entries are whole minutes.
  static const _lockAfterOptions = <int, String>{
    -1: 'Never',
    0: 'Immediately',
    1: 'After 1 minute',
    5: 'After 5 minutes',
    10: 'After 10 minutes',
    30: 'After 30 minutes',
  };

  static const _secureScreenLabels = <SecureScreenMode, String>{
    SecureScreenMode.never: 'Never',
    SecureScreenMode.incognito: 'Incognito',
    SecureScreenMode.always: 'Always',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBiometric = ref.watch(useBiometricLockProvider);
    final lockAfter = ref.watch(lockAfterMinutesProvider);
    final secureMode = ref.watch(secureScreenModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          const PrefSectionHeader('App lock'),
          PrefSwitch(
            title: 'Lock with biometrics',
            subtitle: 'Ask for biometrics or device credentials to open '
                'the app.',
            provider: useBiometricLockProvider,
          ),
          ListTile(
            enabled: useBiometric,
            title: const Text('Lock when idle'),
            subtitle: Text(_lockAfterOptions[lockAfter] ?? 'Immediately'),
            trailing: const Icon(Icons.chevron_right),
            onTap: useBiometric ? () => _pickLockAfter(context, ref) : null,
          ),
          const PrefSectionHeader('Privacy'),
          ListTile(
            title: const Text('Secure screen'),
            subtitle: Text(_secureScreenLabels[secureMode] ?? 'Incognito'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickSecureScreen(context, ref),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Block screenshots and hide the app contents in the recent '
              'apps list.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          PrefSwitch(
            title: 'Hide notification content',
            subtitle: 'Keep titles and cover art out of notifications.',
            provider: hideNotificationContentProvider,
          ),
        ],
      ),
    );
  }

  Future<void> _pickLockAfter(BuildContext context, WidgetRef ref) async {
    final current = ref.read(lockAfterMinutesProvider);
    final picked = await _pickValue<int>(
      context,
      title: 'Lock when idle',
      current: current,
      options: _lockAfterOptions,
    );
    if (picked != null) {
      await ref.read(lockAfterMinutesProvider.notifier).set(picked);
    }
  }

  Future<void> _pickSecureScreen(BuildContext context, WidgetRef ref) async {
    final current = ref.read(secureScreenModeProvider);
    final picked = await _pickValue<SecureScreenMode>(
      context,
      title: 'Secure screen',
      current: current,
      options: _secureScreenLabels,
    );
    if (picked != null) {
      await ref.read(secureScreenModeProvider.notifier).set(picked);
    }
  }

  /// Generic single-choice radio dialog shared by the pickers above.
  Future<T?> _pickValue<T>(
    BuildContext context, {
    required String title,
    required T current,
    required Map<T, String> options,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: current,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in options.entries)
                  RadioListTile<T>(
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
