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

/// Require authentication to open the app.
final appLockEnabledProvider = boolPref('pref_app_lock', false);

/// Apply FLAG_SECURE to the window (block screenshots / recents preview).
final secureScreenProvider = boolPref('secure_screen', false);

/// Grace period in minutes before the app re-locks after going to the
/// background. 0 = lock immediately on leaving.
final lockAfterMinutesProvider = intPref('lock_app_after', 0);
