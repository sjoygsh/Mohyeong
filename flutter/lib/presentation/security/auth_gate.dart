import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/security/secure_screen.dart';
import '../../data/security/security_preferences.dart';
import '../../data/source/incognito_preferences.dart';
import '../tide/tide.dart';

/// Wraps the app behind a biometric / device-credential lock when the
/// app-lock preference is on. Mirrors Mihon's `UnlockActivity` flow:
///
/// - Locks on cold start (when enabled).
/// - Re-locks when the app returns from the background after more than the
///   configured grace period ([lockAfterMinutesProvider]; 0 = immediately).
/// - Keeps the Android `FLAG_SECURE` window flag in sync with
///   [flagSecureProvider].
///
/// Unverified end-to-end — depends on `local_auth` + the secure-flag method
/// channel, neither of which has run on a device yet.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = false;
  // Whether the cold-start lock decision has been resolved from disk yet.
  // Until then we show a neutral splash rather than the protected UI, so the
  // child can never flash before we know whether the lock is enabled.
  bool _ready = false;
  bool _authInProgress = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveInitialLock();
  }

  /// Read the persisted lock state directly from SharedPreferences. We can't
  /// use `ref.read(appLockEnabledProvider)` here: the typed-pref Notifier
  /// returns its default (false) synchronously and only loads the stored
  /// value asynchronously, so reading it on the first frame would report the
  /// lock as disabled and silently bypass it on cold start.
  Future<void> _resolveInitialLock() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Cold-start FLAG_SECURE: derive from the persisted secure-screen mode
    // (stored as the Kotlin enum-name string) and the global incognito state,
    // matching [flagSecureProvider]. The runtime listener below keeps it in
    // sync as either changes.
    final modeRaw = prefs.getString(secureScreenKey);
    final mode = modeRaw == null
        ? SecureScreenMode.incognito
        : secureScreenModeFromStorage(modeRaw);
    final incognito = prefs.getBool(incognitoModeKey) ?? false;
    SecureScreen.setSecure(secureScreenOn(mode, incognito: incognito));
    final enabled = prefs.getBool(appLockKey) ?? false;
    setState(() {
      _ready = true;
      _locked = enabled;
    });
    if (enabled) _authenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appLockEnabledProvider)) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Record the first moment we left the foreground. `inactive` also
        // fires on the way *back* in (inactive -> resumed), so we must not
        // overwrite an earlier timestamp or the idle timer resets to zero
        // and the re-lock is skipped. Including `inactive` here also covers
        // brief backgrounding that never reaches `paused`.
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        if (_shouldRelock()) {
          setState(() => _locked = true);
          _authenticate();
        }
        _pausedAt = null;
      case AppLifecycleState.detached:
        break;
    }
  }

  bool _shouldRelock() {
    if (_locked) return false;
    final pausedAt = _pausedAt;
    if (pausedAt == null) return false;
    final graceMinutes = ref.read(lockAfterMinutesProvider);
    // Mihon's sentinel: -1 is "never re-lock on idle". Without this the
    // negative Duration compares as already-elapsed, so "Never" re-locked
    // the instant the app was backgrounded — the exact opposite of itself.
    if (graceMinutes < 0) return false;
    final elapsed = DateTime.now().difference(pausedAt);
    return elapsed >= Duration(minutes: graceMinutes);
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    _authInProgress = true;
    try {
      // If the device has no biometric hardware and no device credential
      // (PIN/pattern/password) set, the lock can never be satisfied. Don't
      // trap the user on a dead "Unlock" button — let them in instead.
      if (!await _auth.isDeviceSupported()) {
        if (mounted) setState(() => _locked = false);
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Mohyeong',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Keep the lock screen up on any failure; the user can retry.
    } finally {
      _authInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the secure-screen flag in sync with the preference at runtime.
    ref.listen<bool>(flagSecureProvider, (_, next) {
      SecureScreen.setSecure(next);
    });

    // Neutral splash until the persisted lock state is known — never the
    // protected child, which would leak content if the lock is on.
    if (!_ready) return const Scaffold();
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const TideAurora(),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The lock is the whole screen's subject, so it gets the
                  // accent's glow rather than sitting as a grey glyph.
                  Container(
                    width: 74,
                    height: 74,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: TideColors.accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: TideColors.accent.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: TideColors.accent.withValues(alpha: 0.25),
                          blurRadius: 34,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.lock_outlined,
                        size: 30, color: TideColors.accent),
                  ),
                  const SizedBox(height: 26),
                  Text('Locked', style: TideText.display(26)),
                  const SizedBox(height: 8),
                  Text(
                    'Mohyeong is waiting for you.',
                    textAlign: TextAlign.center,
                    style: TideText.body(),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 190,
                    child: TideButton(
                      label: 'Unlock',
                      primary: true,
                      onTap: _authenticate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
