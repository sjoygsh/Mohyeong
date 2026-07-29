/// Security preferences surfaced under Settings → Security, mirroring
/// Mihon's `SettingsSecurityScreen` (`SecurityPreferences.kt`). Keys match
/// the Kotlin app verbatim so a settings import carries values across.
///
/// [useBiometricLockProvider] gates the app behind a biometric / device-
/// credential prompt (see `AuthGate`). [secureScreenModeProvider] chooses
/// when the Android `FLAG_SECURE` window flag is applied (blocks screenshots
/// / hides the app from the recents thumbnail). [lockAfterMinutesProvider]
/// is how long the app may sit in the background before re-locking
/// (-1 = never, 0 = immediately). [hideNotificationContentProvider] hides
/// sensitive text from notifications.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../preferences/typed_preferences.dart';
import '../source/incognito_preferences.dart';

/// SharedPreferences keys. Exposed so [AuthGate] can read the persisted
/// values directly on cold start: the typed-pref Notifiers return their
/// default synchronously and only load the stored value asynchronously,
/// which races the first frame and would report the lock as disabled.
///
/// Mihon keys: `use_biometric_lock`, `secure_screen_v2`, `lock_app_after`,
/// `hide_notification_content`.
const appLockKey = 'use_biometric_lock';

/// Mihon stores the secure-screen mode under `secure_screen_v2` as an enum
/// (NEVER / INCOGNITO / ALWAYS). [AuthGate] consumes a plain bool via
/// [flagSecureProvider] (whether FLAG_SECURE should be on right now); that
/// bool is derived from the mode + global incognito by [secureScreenOn].
const secureScreenKey = 'secure_screen_v2';

const lockAppAfterKey = 'lock_app_after';
const hideNotificationContentKey = 'hide_notification_content';

/// Require biometric / device-credential authentication to open the app.
/// Mihon key `use_biometric_lock`.
final useBiometricLockProvider = boolPref(appLockKey, false);

/// Backwards-compatible alias consumed by `AuthGate` (which references
/// [appLockEnabledProvider] by name). Points at the same notifier so the
/// gate and the settings toggle stay in lockstep.
final appLockEnabledProvider = useBiometricLockProvider;

/// When the Android `FLAG_SECURE` window flag should be applied. Mirrors
/// Mihon's `SecurityPreferences.SecureScreenMode` (stored under
/// `secure_screen_v2`).
enum SecureScreenMode {
  /// FLAG_SECURE only while incognito mode is active.
  incognito('incognito'),

  /// FLAG_SECURE always on.
  always('always'),

  /// FLAG_SECURE never applied.
  never('never');

  const SecureScreenMode(this.storageValue);

  /// The exact string `getEnum` persists in Kotlin (the enum constant name,
  /// upper-cased). Mihon's `getEnum` stores `name`, e.g. `ALWAYS`.
  final String storageValue;
}

/// Mihon `getEnum` persists the enum constant name verbatim (e.g. `ALWAYS`).
/// Map those strings to/from our Dart enum so an imported value resolves.
const _secureScreenModeNames = <String, SecureScreenMode>{
  'ALWAYS': SecureScreenMode.always,
  'INCOGNITO': SecureScreenMode.incognito,
  'NEVER': SecureScreenMode.never,
};

SecureScreenMode secureScreenModeFromStorage(String raw) =>
    _secureScreenModeNames[raw] ?? SecureScreenMode.incognito;

String secureScreenModeToStorage(SecureScreenMode mode) =>
    switch (mode) {
      SecureScreenMode.always => 'ALWAYS',
      SecureScreenMode.incognito => 'INCOGNITO',
      SecureScreenMode.never => 'NEVER',
    };

/// Whether FLAG_SECURE should be on for the given mode. With
/// [SecureScreenMode.incognito] the flag tracks the live global incognito
/// state (see [flagSecureProvider]). 1:1 with Mihon's
/// `SecureActivityDelegate`: `ALWAYS || (INCOGNITO && incognitoMode)`.
bool secureScreenOn(SecureScreenMode mode, {bool incognito = false}) =>
    switch (mode) {
      SecureScreenMode.always => true,
      SecureScreenMode.incognito => incognito,
      SecureScreenMode.never => false,
    };

/// SharedPreferences-backed [Notifier] for the secure-screen mode enum.
/// typed_preferences.dart only provides bool/int/string/string-set helpers
/// (and is off-limits to edit), so the enum mapping lives here. Values are
/// persisted as the Kotlin enum-constant name (e.g. `ALWAYS`) for import
/// parity with Mihon's `getEnum`.
class _SecureScreenModeNotifier extends Notifier<SecureScreenMode> {
  @override
  SecureScreenMode build() {
    _load();
    return SecureScreenMode.incognito;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(secureScreenKey);
    if (stored == null) return;
    final mode = secureScreenModeFromStorage(stored);
    if (mode != state) state = mode;
  }

  Future<void> set(SecureScreenMode value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(secureScreenKey, secureScreenModeToStorage(value));
  }
}

/// Enum-backed picker provider for the secure-screen mode (`secure_screen_v2`).
final secureScreenModeProvider =
    NotifierProvider<_SecureScreenModeNotifier, SecureScreenMode>(
  _SecureScreenModeNotifier.new,
);

/// Derived live view of whether the Android `FLAG_SECURE` window flag should
/// be applied right now: from the secure-screen mode combined with the global
/// incognito state. `AuthGate` listens to this and reflects it onto the host
/// window via the secure-flag method channel. 1:1 with Mihon's
/// `SecureActivityDelegate` combine of `secureScreen` + `incognitoMode`.
final flagSecureProvider = Provider<bool>((ref) {
  final mode = ref.watch(secureScreenModeProvider);
  final incognito = ref.watch(incognitoModeProvider);
  return secureScreenOn(mode, incognito: incognito);
});

/// Grace period in minutes before the app re-locks after going to the
/// background. Mihon key `lock_app_after`: -1 = never, 0 = immediately.
final lockAfterMinutesProvider = intPref(lockAppAfterKey, 0);

/// Hide sensitive content in notifications. Mihon key
/// `hide_notification_content`. Applied by `NotificationService`, which reads
/// the key directly (it posts from the background isolate) and drops the manga
/// or chapter title from the library-update, download-progress and
/// download-error notifications, keeping their generic line.
final hideNotificationContentProvider =
    boolPref(hideNotificationContentKey, false);
