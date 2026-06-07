import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/cover/cover_cache.dart';
import 'data/library/library_update_preference.dart';
import 'data/library/library_update_scheduler.dart';
import 'data/network/app_http_client.dart';
import 'data/notification/notification_service.dart';
import 'data/preferences/appearance_preferences.dart';
import 'data/preferences/theme_preference.dart';
import 'data/shortcuts/shortcut_service.dart';
import 'data/source/extension_repository.dart';
import 'data/source/incognito_preferences.dart';
import 'data/source/installed_extension.dart';
import 'data/source/local_source_preferences.dart';
import 'data/sync/sync_preferences.dart';
import 'data/sync/sync_scheduler.dart';
import 'data/track/tracker_registry.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/onboarding/onboarding_screen.dart';
import 'presentation/security/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final http = await AppHttpClient.instance();
  final storage = await ExtensionStorage.create();
  final prefs = await SharedPreferences.getInstance();
  // Global incognito mode is per-session: clear it on every cold start, as
  // Mihon does in MainActivity. Per-extension incognito persists.
  await prefs.setBool(incognitoModeKey, false);
  final localPrefs = LocalSourcePreferences(prefs);
  final repo = ExtensionRepository(storage, http, localPrefs);
  final coverCache = await CoverCache.create();
  // Create notification channels up front (mirrors Mihon creating them in
  // App.onCreate) so the first notification doesn't have to.
  await NotificationService.instance.init();
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
    // Defer until first frame so the workmanager engine doesn't race the
    // platform channel init.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scheduler = ref.read(libraryUpdateSchedulerProvider);
      final interval = ref.read(libraryUpdatePreferenceProvider);
      scheduler.reschedule(interval);
      // Schedule cross-device sync if enabled, and optionally trigger a
      // one-off sync on app start. Mirrors Mihon's App.onCreate.
      _setupSync();
      // Register launcher shortcuts; selecting one jumps to that home tab
      // (also handles the cold-start shortcut that launched the app).
      ShortcutService.instance.init(
        (tabIndex) => ref.read(homeTabIndexProvider.notifier).set(tabIndex),
      );
    });
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
    final themeMode = ref.watch(themePreferenceProvider);
    final amoled = ref.watch(amoledProvider);
    final seed = AppColorTheme.fromKey(ref.watch(appThemeProvider)).seed;
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
      theme: AppTheme.light(seed),
      darkTheme: amoled ? AppTheme.darkAmoled(seed) : AppTheme.dark(seed),
      themeMode: themeMode,
      home: const AuthGate(
        child: OnboardingGate(child: HomeScreen()),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
