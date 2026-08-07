import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../tide/tide.dart';

/// App-wide Material 3 theme.
///
/// There used to be a `seed` parameter here, fed by an "App theme" picker with
/// fourteen palettes ported from Mihon. It was removed on 2026-07-29: [_tide]
/// overrides primary, secondary, surface, every container and both outlines,
/// and no Tide widget reads the scheme at all — so choosing "Midnight Dusk"
/// changed nothing you could see, and the picker's own swatch showed the raw
/// seed, which is why it rendered blue in a blurple app.
///
/// The seed is now Tide's accent. That is not cosmetic: the handful of slots
/// [_tide] does NOT override (tertiary, error, the inverse pair) are derived
/// from it, so they finally land in the app's own hue family instead of
/// Material's default blue.
class AppTheme {
  AppTheme._();

  /// What every derived scheme slot is generated from — [TideColors.accent].
  /// Duplicated as a literal because `tide.dart` imports nothing from here
  /// and a theme file reaching into the widget layer would invert that.
  static const _seed = Color(0xFFB5ABFC);

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

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
      pageTransitionsTheme: _pageTransitions,
    );
    return _tide(base);
  }

  /// Pull the Material scheme onto Tide's ground and accent.
  ///
  /// This began as scaffolding — a way to stop the not-yet-converted screens
  /// (Updates, History, Browse, More, every settings page) reading as a second
  /// app while they waited their turn. Every one of those is now Tide in its
  /// own right and this theme no longer dresses any screen.
  ///
  /// It stays because Flutter itself still reaches for the scheme: the text
  /// selection handles and cursor, the platform's own dialogs and menus, the
  /// scrollbar, the WebView-adjacent Material bits, and anything a plugin
  /// builds. Those should be blurple-on-ground rather than Material's default
  /// violet-grey. Do not read the presence of a rich theme here as evidence
  /// that some screen still depends on it — see the deleted snackBar /
  /// listTile / progressIndicator blocks below for what "no longer built"
  /// looks like.
  static ThemeData _tide(ThemeData base) {
    // Taken from TideColors rather than restated: this file used to carry its
    // own copy of the ground, which is exactly how a recolour ends up half
    // applied — the Tide surfaces would go black and every Material-owned
    // surface (platform dialogs, menus, the scrollbar) would stay blue-violet.
    const ground = TideColors.ground;
    // The Material container ramp, rebuilt on black. Neutral greys, so nothing
    // Material draws reintroduces the blue-violet cast the ground had.
    const raised = Color(0xFF121212);
    const accent = TideColors.accent;
    const text = TideColors.text;
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      onPrimary: ground,
      secondary: accent,
      onSecondary: ground,
      surface: ground,
      onSurface: text,
      surfaceContainerLowest: ground,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: raised,
      surfaceContainerHigh: const Color(0xFF1C1C1C),
      surfaceContainerHighest: const Color(0xFF242424),
      outline: const Color(0xFF3A3A3A),
      outlineVariant: const Color(0xFF262626),
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
      // No snackBarTheme / listTileTheme / progressIndicatorTheme: the app
      // builds none of those widgets any more. `TideToast`, `TideRow` and
      // `TideSpinner`/`TideProgressBar` replaced them outright, and a theme
      // for a widget that is never constructed is a dead switch — it reads
      // as "the app still shows SnackBars" to whoever edits this next.
      switchTheme: base.switchTheme,
    );
  }

}
