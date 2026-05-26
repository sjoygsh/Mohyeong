import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/theme/app_theme.dart';
import 'presentation/landing/landing_screen.dart';

void main() {
  runApp(const ProviderScope(child: MohyeongApp()));
}

class MohyeongApp extends ConsumerWidget {
  const MohyeongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Mohyeong',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const LandingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
