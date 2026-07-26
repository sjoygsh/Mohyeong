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

  static ThemeData dark(Color seed) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      pageTransitionsTheme: _pageTransitions,
    );
    return _tide(base);
  }

  /// Pull a dark theme onto Tide's ground so the screens that are still plain
  /// Material — Updates, History, Browse, More, every settings page — sit on
  /// the same near-black blue as Tide's own surfaces instead of Material's
  /// default violet-grey, and pick up the blurple accent.
  ///
  /// This is deliberately a theme pass rather than a rewrite: it makes the
  /// whole app coherent in one place, and each screen can then be taken over
  /// properly without the app looking like two apps in the meantime.
  static ThemeData _tide(ThemeData base) {
    const ground = Color(0xFF0D1019);
    const raised = Color(0xFF161A26);
    const accent = Color(0xFFB5ABFC);
    const text = Color(0xFFE9E9ED);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: ground,
      secondary: accent,
      onSecondary: ground,
      surface: ground,
      onSurface: text,
      surfaceContainerLowest: ground,
      surfaceContainerLow: const Color(0xFF12151F),
      surfaceContainer: raised,
      surfaceContainerHigh: const Color(0xFF1B2030),
      surfaceContainerHighest: const Color(0xFF20263A),
      outline: const Color(0xFF3F4457),
      outlineVariant: const Color(0xFF2A2F3E),
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
      canvasColor: ground,
      dividerColor: text.withValues(alpha: 0.10),
      // Headings never bolder than 500, hierarchy from size and space —
      // Nocturne's rule, applied to the Material type ramp too.
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: text,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.18),
        elevation: 0,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(iconColor: Color(0xFF9397AB)),
      // Tide's toast: a floating rounded pane with a hairline edge, not a
      // full-width slab welded to the bottom of the screen. It shares the
      // shape language of the sheets and the nav bar, which is what stops it
      // reading as a piece of a different app arriving for two seconds.
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: raised,
        contentTextStyle: TextStyle(color: text, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        actionTextColor: accent,
      ),
      switchTheme: base.switchTheme,
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    );
  }

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
