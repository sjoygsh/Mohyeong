import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/preferences/theme_preference.dart';
import 'data/source/extension_repository.dart';
import 'data/source/installed_extension.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await ExtensionStorage.create();
  final repo = ExtensionRepository(storage);
  runApp(
    ProviderScope(
      overrides: [
        extensionRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MohyeongApp(),
    ),
  );
}

class MohyeongApp extends ConsumerWidget {
  const MohyeongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themePreferenceProvider);
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
