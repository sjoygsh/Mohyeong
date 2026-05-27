import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/library/library_update_preference.dart';
import 'data/library/library_update_scheduler.dart';
import 'data/network/app_http_client.dart';
import 'data/preferences/theme_preference.dart';
import 'data/source/extension_repository.dart';
import 'data/source/installed_extension.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final http = await AppHttpClient.instance();
  final storage = await ExtensionStorage.create();
  final repo = ExtensionRepository(storage, http);
  runApp(
    ProviderScope(
      overrides: [
        appHttpClientProvider.overrideWithValue(http),
        extensionRepositoryProvider.overrideWithValue(repo),
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themePreferenceProvider);
    // Keep the periodic task in sync with the preference.
    ref.listen<LibraryUpdateInterval>(
      libraryUpdatePreferenceProvider,
      (prev, next) {
        if (prev == next) return;
        ref.read(libraryUpdateSchedulerProvider).reschedule(next);
      },
    );
    return MaterialApp(
      title: 'Mohyeong',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
