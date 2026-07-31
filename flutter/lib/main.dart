import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/backup/backup_preferences.dart';
import 'data/backup/backup_scheduler.dart';
import 'data/cover/cover_cache.dart';
import 'data/library/library_update_preference.dart';
import 'data/library/library_update_scheduler.dart';
import 'data/network/app_http_client.dart';
import 'data/network/webview_http_client.dart';
import 'data/notification/notification_service.dart';
import 'data/shortcuts/shortcut_service.dart';
import 'data/source/extension_repository.dart';
import 'data/source/incognito_preferences.dart';
import 'data/source/installed_extension.dart';
import 'data/source/local_source_preferences.dart';
import 'data/storage/app_cache.dart';
import 'data/sync/sync_preferences.dart';
import 'data/sync/sync_scheduler.dart';
import 'data/track/tracker_registry.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/security/auth_gate.dart';
import 'presentation/tide/tide.dart';
import 'presentation/tide/tide_wordmark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reader pages decode at full resolution (zoom needs it) — 10-15MB each,
  // so Flutter's default 100MB ImageCache holds ~7 and evicts the read-ahead
  // pages before the swipe/scroll reaches them, re-decoding at exactly the
  // moment it stutters. 256MB matches the budget Coil ends up with on the
  // same class of device (25% of a typical largeHeap memory class) in Mihon.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  // These five inits are independent platform-channel round trips — start
  // them all before awaiting any so cold start pays the slowest one, not
  // the sum (they were strictly serial before).
  final httpFuture = AppHttpClient.instance();
  final storageFuture = ExtensionStorage.create();
  final prefsFuture = SharedPreferences.getInstance();
  final coverCacheFuture = CoverCache.create();
  // Create notification channels up front (mirrors Mihon creating them in
  // App.onCreate) so the first notification doesn't have to.
  final notifFuture = NotificationService.instance.init();
  final http = await httpFuture;
  final storage = await storageFuture;
  final prefs = await prefsFuture;
  final coverCache = await coverCacheFuture;
  await notifFuture;
  // Global incognito mode is per-session: clear it on every cold start, as
  // Mihon does in MainActivity. Per-extension incognito persists.
  await prefs.setBool(incognitoModeKey, false);
  // Mihon's autoClearChapterCache: wipe the chapter/image cache on launch
  // when the Data-and-storage switch is on. Fire-and-forget — boot shouldn't
  // wait on filesystem walking.
  if (prefs.getBool('auto_clear_chapter_cache') ?? false) {
    unawaited(AppCache.clear());
  }
  final localPrefs = LocalSourcePreferences(prefs);
  final repo = ExtensionRepository(storage, http, localPrefs);
  runApp(
    ProviderScope(
      overrides: [
        appHttpClientProvider.overrideWithValue(http),
        extensionRepositoryProvider.overrideWithValue(repo),
        coverCacheProvider.overrideWithValue(coverCache),
      ],
      child: const MohyeongApp(),
    ),
  );
}

class MohyeongApp extends ConsumerStatefulWidget {
  const MohyeongApp({super.key});

  @override
  ConsumerState<MohyeongApp> createState() => _MohyeongAppState();
}

class _MohyeongAppState extends ConsumerState<MohyeongApp> {
  @override
  void initState() {
    super.initState();
    // Deferred until after the first frame so the workmanager engine doesn't
    // race the platform channel init. It is NOT additionally held back for the
    // launch wordmark: that was tried and measured, and release cold starts
    // skipped zero frames either way (see TideSplashGate).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundWork();
    });
  }

  void _startBackgroundWork() {
    if (!mounted) return;
    final scheduler = ref.read(libraryUpdateSchedulerProvider);
    final interval = ref.read(libraryUpdatePreferenceProvider);
    scheduler.reschedule(interval);
    // Schedule cross-device sync if enabled, and optionally trigger a
    // one-off sync on app start. Mirrors Mihon's App.onCreate.
    _setupSync();
    // Re-register the periodic auto-backup from the saved interval
    // (Mihon calls BackupCreateJob.setupTask the same way).
    ref
        .read(backupSchedulerProvider)
        .reschedule(ref.read(backupIntervalProvider));
    // Register launcher shortcuts; selecting one jumps to that home tab
    // (also handles the cold-start shortcut that launched the app).
    ShortcutService.instance.init(
      (tabIndex) => ref.read(homeTabIndexProvider.notifier).set(tabIndex),
    );
  }

  /// Re-registers the periodic sync task from the saved auto-sync prefs and,
  /// when `sync on app start` is on with a configured service, kicks off a
  /// one-off sync. 1:1 with Mihon's App.onCreate sync block.
  Future<void> _setupSync() async {
    final prefs = await ref.read(syncPreferencesProvider.future);
    final data = prefs.read();
    final scheduler = ref.read(syncSchedulerProvider);
    await scheduler.reschedule(
      enabled: data.autoSyncEnabled,
      intervalHours: data.autoSyncIntervalHours,
      service: data.service,
    );
    if (data.syncOnAppStart && data.service != SyncService.none) {
      await scheduler.runOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the periodic task in sync with the preference.
    ref.listen<LibraryUpdateInterval>(
      libraryUpdatePreferenceProvider,
      (prev, next) {
        if (prev == next) return;
        ref.read(libraryUpdateSchedulerProvider).reschedule(next);
      },
    );
    // Re-register the periodic task when the device restrictions change so the
    // new workmanager Constraints take effect (matches Kotlin's setupTask).
    ref.listen<Set<String>>(
      libraryUpdateDeviceRestrictionProvider,
      (prev, next) {
        if (prev == next) return;
        ref
            .read(libraryUpdateSchedulerProvider)
            .reschedule(ref.read(libraryUpdatePreferenceProvider));
      },
    );
    // Mirror Mihon's persistent incognito notification: show it while global
    // incognito is on, clear it when turned off. (It starts off every cold
    // start — see main() — so there's nothing to show at launch.)
    ref.listen<bool>(
      incognitoModeProvider,
      (prev, next) {
        if (prev == next) return;
        if (next) {
          NotificationService.instance.showIncognito();
        } else {
          NotificationService.instance.cancelIncognito();
        }
      },
    );
    return MaterialApp(
      title: 'Mohyeong',
      navigatorKey: ref.watch(trackerNavigatorKeyProvider),
      // Dark only. The home feed, the series page and the reader are built
      // out of glass over a near-black ground — a light mode would not be the
      // same app with paler colours, it would be a different design. Handing
      // Material a light theme just made every screen the new UI has not
      // reached yet flash white, which is exactly the seam this removes.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      // The wordmark sits OUTSIDE the auth gate on purpose: the lock screen is
      // the app already talking to you, and being asked to unlock before the
      // app has said its own name reads backwards.
      home: const TideSplashGate(
        child: AuthGate(
          child: OnboardingGate(child: HomeScreen()),
        ),
      ),
      builder: buildAppShell,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Everything that wraps the navigator: the hidden WebView host, and the
/// text-style floor every screen inherits.
///
/// Named and top-level so the floor can be tested — see
/// `test/app_shell_text_style_test.dart`.
Widget buildAppShell(BuildContext context, Widget? child) {
  // WidgetsApp installs a deliberately alarming DefaultTextStyle — 48px red
  // monospace with a DOUBLE YELLOW UNDERLINE — as the app-wide floor, so that
  // text with no Material above it announces itself. Material and Scaffold
  // override it, which is why ordinary screens look right, but ANYTHING
  // outside a Material subtree inherits it: the root overlay (where toasts
  // are inserted), the splash veil, and these builder-level siblings. The
  // `TideText.*` helpers set colour, size and weight but never `decoration`,
  // so the merge kept exactly one part of that fallback — the yellow bars.
  //
  // Installing the floor HERE fixes all of them at once: this wraps the
  // navigator, so it is an ancestor of every route AND of the root overlay.
  // Material still wins inside routes, so screens are unaffected.
  return DefaultTextStyle(
    style: TideText.body().copyWith(decoration: TextDecoration.none),
    child: Stack(
      children: [
        // Mounted full-size but BEHIND the app: Cloudflare's challenge needs a
        // real viewport to run, and the opaque UI on top keeps it invisible.
        // (A 1×1 viewport gets flagged and never solves.)
        const Positioned.fill(child: OffscreenWebViewHost()),
        if (child != null) Positioned.fill(child: child),
      ],
    ),
  );
}
