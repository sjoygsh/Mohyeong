/// First-run onboarding flow, a 1:1 port of Mihon's `OnboardingScreen`
/// (`eu.kanade.presentation.more.onboarding`).
///
/// Mihon hosts the steps inside an `InfoScreen` (rocket icon, heading,
/// subtitle, an accept button that reads "Next" until the final step where
/// it becomes "Finish"), with the accept button enabled only when the
/// current step's `isComplete` is true. Steps, in order:
///
///   1. Theme       — always complete
///   2. Storage     — complete once a storage location is chosen (gated)
///   3. Permission  — always complete
///   4. Guides      — always complete
///
/// Back navigation walks to the previous step; on the first step it's a
/// no-op (Mihon blocks leaving onboarding until it's finished). Finishing
/// sets `__APP_STATE_onboarding_complete`.
///
/// Functional adaptations from the Kotlin original: the Permission step omits
/// the install-unknown-apps row (Mohyeong's extensions are JS, not APKs) and
/// the telemetry switches (no analytics/crashlytics in Mohyeong); the Theme
/// step omits the colour-palette picker (Mohyeong has no palette variants
/// yet). Everything else mirrors Mihon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/onboarding/onboarding_preferences.dart';
import '../../data/preferences/appearance_preferences.dart';
import '../../data/preferences/theme_preference.dart';
import '../../data/source/local_source_preferences.dart';
import '../../data/source/saf.dart';
import '../../data/system/app_permissions.dart';
import '../backup/backup_screen.dart';

const String _storageHelpUrl =
    'https://sjoygsh.github.io/Mohyeong/help.html#storage';
const String _gettingStartedUrl =
    'https://sjoygsh.github.io/Mohyeong/help.html#getting-started';

/// Wraps [child] behind the onboarding flow until it's been completed once.
/// Reads the persisted flag directly on cold start (rather than via the
/// async-loading Notifier) so the real app never flashes before we know
/// whether onboarding is needed — same reasoning as AuthGate.
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  bool _ready = false;
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // The Notifier kicks off its disk read in build(); give it a microtask
    // turn to settle so we don't gate on the stale default, then read the
    // now-current state.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() {
      _ready = true;
      _complete = ref.read(onboardingCompleteProvider);
    });
    // Keep watching in case the disk value resolves a frame later on slow
    // storage, or onboarding completes while this gate is mounted.
    ref.listenManual(onboardingCompleteProvider, (_, next) {
      if (mounted && next != _complete) setState(() => _complete = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold();
    if (_complete) return widget.child;
    return OnboardingScreen(
      onFinish: () async {
        await ref.read(onboardingCompleteProvider.notifier).set(true);
        if (mounted) setState(() => _complete = true);
      },
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onFinish});

  final Future<void> Function() onFinish;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _stepCount = 4;
  int _current = 0;

  bool get _isLast => _current == _stepCount - 1;

  /// Mirrors `canAccept = steps[currentStep].isComplete`. Only the Storage
  /// step (index 1) gates; the rest are always complete.
  bool _canAccept(WidgetRef ref) {
    if (_current == 1) return ref.watch(storageDirProvider) != null;
    return true;
  }

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      setState(() => _current += 1);
    }
  }

  void _back() {
    if (_current > 0) setState(() => _current -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final canAccept = _canAccept(ref);
    final theme = Theme.of(context);
    return PopScope(
      // Block leaving onboarding until finished; the in-flow back button
      // walks to the previous step instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  children: [
                    Icon(
                      Icons.rocket_launch_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome!',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Let's set some things up first. You can always change "
                      'these in the settings later too.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0.15, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(
                      position: offset,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: SingleChildScrollView(
                    key: ValueKey<int>(_current),
                    padding: const EdgeInsets.all(24),
                    child: _stepContent(_current),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Step ${_current + 1} of $_stepCount',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: canAccept ? _next : null,
                      child: Text(_isLast ? 'Get started' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepContent(int index) {
    switch (index) {
      case 0:
        return const _ThemeStep();
      case 1:
        return const _StorageStep();
      case 2:
        return const _PermissionStep();
      default:
        return const _GuidesStep();
    }
  }
}

// -----------------------------------------------------------------------------
// Step 1 — Theme
// -----------------------------------------------------------------------------

class _ThemeStep extends ConsumerWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider);
    final amoled = ref.watch(amoledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<ThemeMode>(
          groupValue: themeMode,
          onChanged: (m) {
            if (m != null) ref.read(themePreferenceProvider.notifier).setMode(m);
          },
          child: const Column(
            children: [
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                title: Text('Follow system'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                title: Text('Light'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                title: Text('Dark'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('AMOLED black'),
          subtitle: const Text('Use a pure-black background in dark mode.'),
          value: amoled,
          onChanged: (v) => ref.read(amoledProvider.notifier).set(v),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Step 2 — Storage (SAF)
// -----------------------------------------------------------------------------

class _StorageStep extends ConsumerStatefulWidget {
  const _StorageStep();

  @override
  ConsumerState<_StorageStep> createState() => _StorageStepState();
}

class _StorageStepState extends ConsumerState<_StorageStep> {
  String? _displayName;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _refreshName();
  }

  Future<void> _refreshName() async {
    final uri = ref.read(storageDirProvider);
    if (uri == null) {
      if (mounted) setState(() => _displayName = null);
      return;
    }
    final name = Saf.isContentUri(uri) ? await Saf.displayName(uri) : uri;
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final uri = await Saf.openTree();
      if (uri != null) {
        await ref.read(storageDirProvider.notifier).set(uri);
        await _refreshName();
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = ref.watch(storageDirProvider);
    final theme = Theme.of(context);
    final selected =
        uri == null ? 'No storage location set' : (_displayName ?? uri);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select a folder where Mohyeong will store chapter downloads, '
          'backups, and more.\n\nA dedicated folder is recommended.\n\n'
          'Selected folder: $selected',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _picking ? null : _pick,
          child: const Text('Select a folder'),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Updating from an older version and not sure what to select? Refer '
          'to the storage guide for more information.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => _openUrl(_storageHelpUrl),
          child: const Text('Storage guide'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Step 3 — Permissions
// -----------------------------------------------------------------------------

class _PermissionStep extends ConsumerStatefulWidget {
  const _PermissionStep();

  @override
  ConsumerState<_PermissionStep> createState() => _PermissionStepState();
}

class _PermissionStepState extends ConsumerState<_PermissionStep>
    with WidgetsBindingObserver {
  bool _notifications = false;
  bool _battery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check grants when returning from a system settings dialog — mirrors
    // Mihon's DisposableEffect lifecycle observer.
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    final n = await AppPermissions.hasNotificationPermission();
    final b = await AppPermissions.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _notifications = n;
        _battery = b;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PermissionRow(
          title: 'Notification permission',
          subtitle: 'Get notified for library updates and more.',
          granted: _notifications,
          onRequest: () async {
            await AppPermissions.requestNotificationPermission();
            await _recheck();
          },
        ),
        _PermissionRow(
          title: 'Background battery usage',
          subtitle: 'Avoid interruptions to long-running library updates, '
              'downloads, and backup restores.',
          granted: _battery,
          onRequest: () async {
            await AppPermissions.requestIgnoreBatteryOptimizations();
            // Re-check happens on resume via the lifecycle observer.
          },
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onRequest,
  });

  final String title;
  final String subtitle;
  final bool granted;
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted
          ? const Icon(Icons.check_circle, color: Colors.green)
          : OutlinedButton(
              onPressed: () => onRequest(),
              child: const Text('Grant'),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Step 4 — Guides
// -----------------------------------------------------------------------------

class _GuidesStep extends StatelessWidget {
  const _GuidesStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'New to Mohyeong? We recommend checking out the getting started '
          'guide.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => _openUrl(_gettingStartedUrl),
          child: const Text('Getting started guide'),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Reinstalling Mohyeong?',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
          ),
          child: const Text('Restore backup'),
        ),
      ],
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
