import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// The colour palettes Mihon ships under Settings → Appearance → "App theme"
/// (Kotlin `eu.kanade.domain.ui.model.AppTheme`). [key] is the Kotlin enum
/// name so the `pref_app_theme` value imports across without translation.
///
/// Mihon hand-tunes a full light + dark [ColorScheme] per theme; here we drive
/// each from its brand "key colour" through [ColorScheme.fromSeed], which
/// reproduces the accent faithfully while letting Material 3 derive the rest.
/// [MONET] (Material You / dynamic colour) has no Flutter wiring yet, so it
/// falls back to the default seed.
enum AppColorTheme {
  defaultTheme('DEFAULT', 'Default', Color(0xFF2979FF)),
  monet('MONET', 'Dynamic (Material You)', Color(0xFF2979FF)),
  catppuccin('CATPPUCCIN', 'Catppuccin', Color(0xFF8839EF)),
  greenApple('GREEN_APPLE', 'Green Apple', Color(0xFF188140)),
  lavender('LAVENDER', 'Lavender', Color(0xFFA177FF)),
  midnightDusk('MIDNIGHT_DUSK', 'Midnight Dusk', Color(0xFFF02475)),
  nord('NORD', 'Nord', Color(0xFF5E81AC)),
  strawberryDaiquiri(
      'STRAWBERRY_DAIQUIRI', 'Strawberry Daiquiri', Color(0xFFED4A65)),
  tako('TAKO', 'Tako', Color(0xFFF3B375)),
  tealTurquoise('TEALTURQUOISE', 'Teal & Turquoise', Color(0xFF008080)),
  tidalWave('TIDAL_WAVE', 'Tidal Wave', Color(0xFF004152)),
  yinYang('YINYANG', 'Yin & Yang', Color(0xFF000000)),
  yotsuba('YOTSUBA', 'Yotsuba', Color(0xFFAE3200)),
  monochrome('MONOCHROME', 'Monochrome', Color(0xFF5E5E5E));

  const AppColorTheme(this.key, this.label, this.seed);

  /// Kotlin `AppTheme` enum name; the stored `pref_app_theme` value.
  final String key;

  /// Human-readable label shown in the picker.
  final String label;

  /// Seed colour fed to [ColorScheme.fromSeed].
  final Color seed;

  /// Resolve a stored `pref_app_theme` value, falling back to [defaultTheme]
  /// for unknown / deprecated (DARK_BLUE, HOT_PINK, BLUE) names.
  static AppColorTheme fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return defaultTheme;
  }
}

/// App-wide Material 3 themes, built from the active [AppColorTheme] seed.
class AppTheme {
  AppTheme._();

  /// Screen push/pop transition: Material shared-axis X (30dp slide + fade),
  /// the same motion Mihon's `DefaultNavigatorScreenTransition` applies to
  /// every Voyager push/pop via `materialSharedAxisX` (Navigator.kt). Also
  /// lighter per frame than Flutter's default Android Zoom transition, which
  /// scales both routes.
  static const _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: SharedAxisPageTransitionsBuilder(
        transitionType: SharedAxisTransitionType.horizontal,
      ),
    },
  );

  static ThemeData light(Color seed) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        pageTransitionsTheme: _pageTransitions,
      );

  static ThemeData dark(Color seed) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        pageTransitionsTheme: _pageTransitions,
      );

  /// Pure-black dark variant for OLED screens. Same seed-derived accent
  /// colours as [dark], but surfaces/background collapse to black so dark
  /// pixels draw no power. Selected when the AMOLED pref is on.
  static ThemeData darkAmoled(Color seed) {
    final base = dark(seed);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      colorScheme: base.colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF101010),
      ),
    );
  }
}
