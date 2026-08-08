/// First-run onboarding flow, a 1:1 port of Mihon's `OnboardingScreen`
/// (`eu.kanade.presentation.more.onboarding`).
///
/// Mihon hosts the steps inside an `InfoScreen` (rocket icon, heading,
/// subtitle, an accept button that reads "Next" until the final step where
/// it becomes "Finish"), with the accept button enabled only when the
/// current step's `isComplete` is true. Steps, in order:
///
///   1. Storage     — complete once a storage location is chosen (gated)
///   2. Permission  — always complete
///   3. Guides      — always complete
///
/// Back navigation walks to the previous step; on the first step it's a
/// no-op (Mihon blocks leaving onboarding until it's finished). Finishing
/// sets `__APP_STATE_onboarding_complete`.
///
/// Functional adaptations from the Kotlin original: the Permission step omits
/// the install-unknown-apps row (Mohyeong's extensions are JS, not APKs) and
/// the telemetry switches (no analytics/crashlytics in Mohyeong). Mihon's
/// Theme step is gone entirely — Mohyeong is built dark with no palette
/// variants, so the step had nothing to set and only explained its own
/// absence. Everything else mirrors Mihon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/onboarding/onboarding_preferences.dart';
import '../../data/source/local_source_preferences.dart';
import '../../data/source/saf.dart';
import '../../data/system/app_permissions.dart';
import '../backup/backup_screen.dart';
import '../tide/tide.dart';

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
  static const int _stepCount = 3;
  int _current = 0;

  bool get _isLast => _current == _stepCount - 1;

  /// Mirrors `canAccept = steps[currentStep].isComplete`. Only the Storage
  /// step (index 0) gates; the rest are always complete.
  bool _canAccept(WidgetRef ref) {
    if (_current == 0) return ref.watch(storageDirProvider) != null;
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
    const titles = ['Storage', 'Permissions', 'Guides'];
    return PopScope(
      // Block leaving onboarding until finished; the in-flow back button
      // walks to the previous step instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: TideColors.ground,
        body: Stack(
          children: [
            const TideAurora(),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WELCOME',
                            style: TideText.kicker(
                                    size: 12,
                                    color: TideColors.textAt(0.45))
                                .copyWith(letterSpacing: 2.4)),
                        const SizedBox(height: 10),
                        Text(titles[_current], style: TideText.display(30)),
                        const SizedBox(height: 8),
                        Text(
                          "A few things to set up. All of it can be changed "
                          'later in settings.',
                          style: TideText.body(),
                        ),
                        const SizedBox(height: 20),
                        // The steps as a row of lit rules: the one you are on
                        // takes the accent, the ones behind you stay bright,
                        // and what's ahead is dim. Progress you can read
                        // without a "3 of 4".
                        Row(
                          children: [
                            for (var i = 0; i < _stepCount; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 320),
                                  curve: tideEase,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    color: i == _current
                                        ? TideColors.accent
                                        : Colors.white.withValues(
                                            alpha: i < _current ? 0.34 : 0.10),
                                    boxShadow: i == _current
                                        ? [
                                            BoxShadow(
                                              color: TideColors.accent
                                                  .withValues(alpha: 0.5),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
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
                          child:
                              FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: SingleChildScrollView(
                        key: ValueKey<int>(_current),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: _stepContent(_current),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 22),
                    child: Opacity(
                      // The gate is the Storage step with no folder picked.
                      // Dimming says "not yet" where a dead button says
                      // nothing at all.
                      opacity: canAccept ? 1 : 0.4,
                      child: TideButton(
                        label: _isLast ? 'Get started' : 'Next',
                        primary: true,
                        onTap: canAccept ? _next : () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepContent(int index) {
    switch (index) {
      case 0:
        return const _StorageStep();
      case 1:
        return const _PermissionStep();
      default:
        return const _GuidesStep();
    }
  }
}

// -----------------------------------------------------------------------------
// Step 1 — Storage (SAF)
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
    final chosen = uri != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick a folder for chapter downloads, backups, and more. A '
          'dedicated folder is recommended.',
          style: TideText.body(),
        ),
        const SizedBox(height: 18),
        // The chosen folder is the state of this step, so it takes the lit
        // row rather than being buried in a paragraph.
        TideRow(
          icon: chosen ? Icons.folder_outlined : Icons.folder_off_outlined,
          title: chosen ? (_displayName ?? uri) : 'No folder yet',
          subtitle: chosen ? 'Tap to change' : 'Required to continue',
          lit: chosen,
          onTap: _picking ? null : _pick,
        ),
        const SizedBox(height: 26),
        Text(
          'Updating from an older version and not sure what to pick?',
          style: TideText.body(),
        ),
        const SizedBox(height: 12),
        TideButton(
          label: 'Storage guide',
          onTap: () => _openUrl(_storageHelpUrl),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Step 2 — Permissions
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
          subtitle: 'Get notified for library updates and more',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TideGlass(
        radius: TideRadius.pane,
        tintTop: granted ? 0.125 : 0.06,
        tintBottom: granted ? 0.045 : 0.02,
        highlight: granted ? 0.19 : 0.12,
        border: granted ? 0.20 : 0.08,
        onTap: granted ? null : () => onRequest(),
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TideText.title()),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TideText.caption(size: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (granted)
              Icon(Icons.check_rounded, size: 19, color: TideColors.accent)
            else
              Text(
                'Grant',
                style: TideText.title(size: 13, color: TideColors.accent),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Step 3 — Guides
// -----------------------------------------------------------------------------

class _GuidesStep extends StatelessWidget {
  const _GuidesStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'New here? The getting started guide covers adding sources and '
          'building a library.',
          style: TideText.body(),
        ),
        const SizedBox(height: 16),
        TideRow(
          icon: Icons.menu_book_outlined,
          title: 'Getting started guide',
          subtitle: 'Opens in your browser',
          trailing: const TideChevron(),
          onTap: () => _openUrl(_gettingStartedUrl),
        ),
        const SizedBox(height: 26),
        Text('Coming back to Mohyeong?', style: TideText.body()),
        const SizedBox(height: 16),
        TideRow(
          icon: Icons.settings_backup_restore,
          title: 'Restore a backup',
          subtitle: 'Bring over an existing library',
          trailing: const TideChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
          ),
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
