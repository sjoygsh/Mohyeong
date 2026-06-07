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
    0: 'Always',
    1: 'After 1 minute',
    2: 'After 2 minutes',
    5: 'After 5 minutes',
    10: 'After 10 minutes',
    -1: 'Never',
  };

  static const _secureScreenLabels = <SecureScreenMode, String>{
    SecureScreenMode.always: 'Always',
    SecureScreenMode.incognito: 'Incognito mode',
    SecureScreenMode.never: 'Never',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBiometric = ref.watch(useBiometricLockProvider);
    final lockAfter = ref.watch(lockAfterMinutesProvider);
    final secureMode = ref.watch(secureScreenModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Security and privacy')),
      body: ListView(
        children: [
          const PrefSectionHeader('Security'),
          PrefSwitch(
            title: 'Require unlock',
            provider: useBiometricLockProvider,
          ),
          ListTile(
            enabled: useBiometric,
            title: const Text('Lock when idle'),
            subtitle: Text(_lockAfterOptions[lockAfter] ?? 'Always'),
            trailing: const Icon(Icons.chevron_right),
            onTap: useBiometric ? () => _pickLockAfter(context, ref) : null,
          ),
          PrefSwitch(
            title: 'Hide notification content',
            provider: hideNotificationContentProvider,
          ),
          ListTile(
            title: const Text('Secure screen'),
            subtitle:
                Text(_secureScreenLabels[secureMode] ?? 'Incognito mode'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickSecureScreen(context, ref),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Secure screen hides app contents when switching apps and '
              'block screenshots',
              style: TextStyle(fontSize: 12),
            ),
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
