import 'package:flutter/material.dart';

/// App-wide Material 3 themes.
///
/// Placeholder for v1.0 scaffold. Will be expanded to mirror the existing
/// Kotlin app's theming (M3 dynamic color, custom seed, dark/light variants).
class AppTheme {
  AppTheme._();

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ),
  );

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    ),
  );
}
