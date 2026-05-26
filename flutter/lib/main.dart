import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/preferences/theme_preference.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/home/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: MohyeongApp()));
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
