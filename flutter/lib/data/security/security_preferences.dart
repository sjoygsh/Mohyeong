/// Security preferences surfaced under Settings → Security, mirroring
/// Mihon's `SettingsSecurityScreen`. Keys match the Kotlin app where one
/// exists so a settings import carries across.
///
/// [appLockEnabledProvider] gates the app behind a biometric / device-
/// credential prompt (see `AuthGate`). [secureScreenProvider] toggles the
/// Android `FLAG_SECURE` window flag (blocks screenshots / hides the app
/// from the recents thumbnail). [lockAfterMinutesProvider] is how long the
/// app may sit in the background before re-locking (0 = lock immediately).
library;

import '../preferences/typed_preferences.dart';

/// SharedPreferences keys. Exposed so [AuthGate] can read the persisted
/// values directly on cold start: the typed-pref Notifiers return their
/// default synchronously and only load the stored value asynchronously,
/// which races the first frame and would report the lock as disabled.
const appLockKey = 'pref_app_lock';
const secureScreenKey = 'secure_screen';

/// Require authentication to open the app.
final appLockEnabledProvider = boolPref(appLockKey, false);

/// Apply FLAG_SECURE to the window (block screenshots / recents preview).
final secureScreenProvider = boolPref(secureScreenKey, false);

/// Grace period in minutes before the app re-locks after going to the
/// background. 0 = lock immediately on leaving.
final lockAfterMinutesProvider = intPref('lock_app_after', 0);
