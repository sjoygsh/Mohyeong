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

  /// Pure-black dark variant for OLED screens. Same seed-derived accent
  /// colours as [dark], but surfaces/background collapse to black so dark
  /// pixels draw no power. Selected when the AMOLED pref is on.
  static final ThemeData darkAmoled = dark.copyWith(
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    colorScheme: dark.colorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF101010),
    ),
  );
}
