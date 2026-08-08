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
    return PrefScaffold(
      title: 'Security and privacy',
      actions: [const PrefHelp('security')],
      children: [
          const PrefSectionHeader('Security'),
          PrefSwitch(
            title: 'Require unlock',
            provider: useBiometricLockProvider,
          ),
          PrefRow(
            icon: Icons.timer_outlined,
            title: 'Lock when idle',
            subtitle: _lockAfterOptions[lockAfter] ?? 'Always',
            onTap: useBiometric ? () => _pickLockAfter(context, ref) : null,
          ),
          PrefSwitch(
            title: 'Hide notification content',
            subtitle: 'Hides manga and chapter titles',
            provider: hideNotificationContentProvider,
          ),
          PrefRow(
            icon: Icons.visibility_off_outlined,
            title: 'Secure screen',
            subtitle: _secureScreenLabels[secureMode] ?? 'Incognito mode',
            onTap: () => _pickSecureScreen(context, ref),
          ),
          const PrefNote(
            'Secure screen hides app contents when switching apps and blocks '
            'screenshots.',
          ),
        ],
    );
  }

  Future<void> _pickLockAfter(BuildContext context, WidgetRef ref) async {
    final current = ref.read(lockAfterMinutesProvider);
    final picked = await pickPref<int>(
      context,
      title: 'Lock when idle',
      selected: current,
      options: [
        for (final e in _lockAfterOptions.entries) (e.key, e.value),
      ],
    );
    if (picked != null) {
      await ref.read(lockAfterMinutesProvider.notifier).set(picked);
    }
  }

  Future<void> _pickSecureScreen(BuildContext context, WidgetRef ref) async {
    final current = ref.read(secureScreenModeProvider);
    final picked = await pickPref<SecureScreenMode>(
      context,
      title: 'Secure screen',
      selected: current,
      options: [
        for (final e in _secureScreenLabels.entries) (e.key, e.value),
      ],
    );
    if (picked != null) {
      await ref.read(secureScreenModeProvider.notifier).set(picked);
    }
  }

}
