// ===========================================================================
// Tide — the app's own visual language.
//
// Ported from the "Tide: Glass Manhwa Reader" design (Tide Reader.dc.html) and
// the Nocturne token sheet it consumes. Nocturne supplies the palette and the
// type discipline: a near-neutral blue-grey ground, one blurple accent used as
// a LINE and a GLOW rather than a flood, headings capped at weight 500 with
// hierarchy carried by size and space, and low chroma everywhere the accent
// isn't. Tide adds the glass: translucent panels that float over drifting
// aurora light.
//
// This file is the token layer plus the primitives every Tide screen builds
// from. Nothing here reads app state — it is presentation only.
// ===========================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cover/cover_cache.dart';
import '../../data/source/extension_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';

/// Nocturne's palette, plus the grounds the Tide screens paint on.
///
/// The ramps are the design system's own OKLCH-derived steps; prefer a named
/// step over an ad-hoc blend so the same visual weight shows up everywhere.
abstract final class TideColors {
  /// Home / series ground. Nocturne's `--color-bg` shifted a touch cooler and
  /// darker so the aurora behind it has somewhere to glow.
  static const ground = Color(0xFF0D1019);

  /// Reader ground — darker still: page art is the only thing that should
  /// carry light while reading.
  static const readerGround = Color(0xFF07080E);

  /// Aurora blobs (blurred radial washes behind the home screen).
  static const auroraViolet = Color(0xFF4A3F8F);
  static const auroraBlue = Color(0xFF25506E);
  static const auroraIndigo = Color(0xFF2B2A5E);

  /// `--color-text`, and the brightest neutral step for display type.
  static const text = Color(0xFFE9E9ED);
  static const textBright = Color(0xFFF3F5FE); // --color-neutral-100

  /// Accent ramp. [accent] is the working step — the one that draws lines,
  /// marks and glows. [accentLight] is its lit state, [accentDeep] the shaded
  /// one used in gradients.
  static const accent = Color(0xFFB5ABFC); // --color-accent-400
  static const accentLight = Color(0xFFD2CEFD); // --color-accent-300
  static const accentDeep = Color(0xFF8D81D6);

  /// Text at [opacity] — the design expresses muted type as alpha over the
  /// one text colour rather than as separate greys.
  static Color textAt(double opacity) => text.withValues(alpha: opacity);

  /// Bright display type at [opacity].
  static Color brightAt(double opacity) =>
      textBright.withValues(alpha: opacity);
}

/// Type scale. Nocturne pairs one family across headings and body and never
/// bolds past 500 — hierarchy is size, spacing and colour.
///
/// CSS letter-spacing is in `em`; Flutter's is logical pixels, so every
/// tracking value here is the design's em value multiplied by its font size.
abstract final class TideText {
  /// Section label / eyebrow: uppercase, widely tracked, quiet.
  static TextStyle kicker({Color? color, double size = 11}) => TextStyle(
        fontSize: size,
        height: 1.2,
        letterSpacing: size * 0.18,
        fontWeight: FontWeight.w500,
        color: color ?? TideColors.textAt(0.42),
      );

  /// Hero title — the largest type in the app.
  static TextStyle display(double size) => TextStyle(
        fontSize: size,
        height: 1.02,
        letterSpacing: size * -0.035,
        fontWeight: FontWeight.w500,
        color: TideColors.textBright,
      );

  /// Row / card title.
  static TextStyle title({double size = 14.5, Color? color}) => TextStyle(
        fontSize: size,
        height: 1.25,
        letterSpacing: size * -0.015,
        fontWeight: FontWeight.w500,
        color: color ?? TideColors.text,
      );

  /// Supporting line under a title.
  static TextStyle caption({double size = 11.5, double opacity = 0.45}) =>
      TextStyle(
        fontSize: size,
        height: 1.3,
        color: TideColors.textAt(opacity),
      );

  /// Reading copy — the one place line-height opens up.
  static TextStyle body() => TextStyle(
        fontSize: 14,
        height: 1.62,
        color: TideColors.textAt(0.68),
      );
}

/// Backdrop saturation boost, matching the design's `saturate(160–190%)` on
/// every glass panel: what shows through a pane comes back richer, not just
/// blurrier. Standard luminance-preserving saturation matrix.
ColorFilter _saturate(double s) {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return ColorFilter.matrix(<double>[
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Strokes a rounded rect with a top-lit gradient edge.
///
/// The design draws two things on every glass panel: a hairline border and an
/// `inset 0 1px 0` white highlight along its top. Flutter has no inset shadow,
/// but the pair reads as one lit edge — brightest where light would strike the
/// top bevel, fading around to the bottom — so it is painted as a single
/// gradient stroke.
class _GlassEdge extends CustomPainter {
  const _GlassEdge({
    required this.radius,
    required this.highlight,
    required this.border,
  });

  final double radius;

  /// Alpha of the top of the stroke (the CSS inset highlight).
  final double highlight;

  /// Alpha of the rest of the stroke (the CSS border).
  final double border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            Colors.white.withValues(alpha: highlight),
            Colors.white.withValues(alpha: border),
            Colors.white.withValues(alpha: border * 0.75),
          ],
          const [0.0, 0.35, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge old) =>
      old.radius != radius ||
      old.highlight != highlight ||
      old.border != border;
}

/// A pane of Tide glass: a translucent top-lit gradient with a lit edge, and
/// — when it floats over content rather than over the flat ground — a real
/// backdrop blur.
///
/// [blur] is deliberately opt-in. Every `BackdropFilter` forces a `saveLayer`,
/// and the design's list rows sit on a flat dark ground where a blur has
/// nothing to reveal. Panes that float over artwork (the tab bar, the reader
/// chrome, the continue bar) pass `blur: true` and get the real thing.
class TideGlass extends StatelessWidget {
  const TideGlass({
    super.key,
    required this.child,
    this.radius = 18,
    this.blur = false,
    this.tintTop = 0.075,
    this.tintBottom = 0.028,
    this.highlight = 0.13,
    this.border = 0.09,
    this.saturation = 1.6,
    this.sigma = 15,
    this.padding,
    this.shadows,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final bool blur;

  /// Alpha of the panel's own gradient fill, top and bottom.
  final double tintTop;
  final double tintBottom;

  /// Edge stroke alphas — see [_GlassEdge].
  final double highlight;
  final double border;

  final double saturation;

  /// Gaussian sigma for [blur]. The design specifies a 30px CSS blur; CSS
  /// measures the standard deviation at twice Flutter's sigma.
  final double sigma;

  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: tintTop),
            Colors.white.withValues(alpha: tintBottom),
          ],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _GlassEdge(
          radius: radius,
          highlight: highlight,
          border: border,
        ),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );

    if (blur) {
      pane = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: _saturate(saturation),
          inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        ),
        child: pane,
      );
    }

    pane = ClipRRect(borderRadius: shape, child: pane);

    if (shadows != null) {
      pane = DecoratedBox(
        decoration: BoxDecoration(borderRadius: shape, boxShadow: shadows),
        child: pane,
      );
    }
    if (onTap != null) {
      // Transparent rather than opaque: the pane paints its own surface, and
      // a Material ink splash would fight the glass.
      pane = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pane,
      );
    }
    return pane;
  }
}

/// One drifting wash of colour behind the home screen. Sized by its parent —
/// [TideAurora] measures once and hands each blob a concrete box.
class _AuroraBlob extends StatefulWidget {
  const _AuroraBlob({
    required this.color,
    required this.size,
    required this.from,
    required this.to,
    required this.period,
  });

  final Color color;
  final Size size;

  /// Start / mid keyframes: `(translateX, translateY, scale)`, translation in
  /// fractions of the blob's own size — the design's `translate(%)`.
  final (double, double, double) from;
  final (double, double, double) to;

  /// One half-cycle. The CSS keyframes run 0% → 50% → 100% with the ends
  /// equal, which is exactly a reversing repeat over half the stated duration.
  final Duration period;

  @override
  State<_AuroraBlob> createState() => _AuroraBlobState();
}

class _AuroraBlobState extends State<_AuroraBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);

  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.size.width;
    final h = widget.size.height;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        final dx = ui.lerpDouble(widget.from.$1, widget.to.$1, v)!;
        final dy = ui.lerpDouble(widget.from.$2, widget.to.$2, v)!;
        final s = ui.lerpDouble(widget.from.$3, widget.to.$3, v)!;
        return Transform.translate(
          offset: Offset(w * dx, h * dy),
          child: Transform.scale(scale: s, child: child),
        );
      },
      // The design blurs these by 70px on top of the radial falloff. A soft
      // multi-stop radial IS that blur, and costs a shader instead of a
      // full-screen filter on every frame of a continuously-running
      // animation — which on a phone is the difference between free and not.
      //
      // The RepaintBoundary is load-bearing: it gives the gradient its own
      // layer, so the transform above re-composites a cached raster each
      // frame instead of re-running a screen-sized shader. Without it three
      // of these animating at once cost real frames on a mid-range phone.
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.color,
                widget.color.withValues(alpha: 0.55),
                widget.color.withValues(alpha: 0.18),
                widget.color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.35, 0.62, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Geometry of one blob, as fractions of the aurora field.
typedef _BlobSpec = ({
  Color color,
  Rect rect,
  (double, double, double) from,
  (double, double, double) to,
  Duration period,
});

/// The drifting light behind the home screen: three slow, overlapping washes
/// on a dark ground. Nothing reacts to it and it never repeats visibly — it
/// exists to keep the ground from reading as flat black behind glass.
class TideAurora extends StatelessWidget {
  const TideAurora({super.key, this.opacity = 0.72});

  final double opacity;

  static const _blobs = <_BlobSpec>[
    (
      color: TideColors.auroraViolet,
      rect: Rect.fromLTWH(-0.05, 0, 0.70, 0.55),
      from: (-0.06, -0.04, 1.0),
      to: (0.10, 0.08, 1.28),
      period: Duration(seconds: 13),
    ),
    (
      color: TideColors.auroraBlue,
      rect: Rect.fromLTWH(0.45, 0.18, 0.65, 0.50),
      from: (0.08, 0.06, 1.15),
      to: (-0.08, -0.10, 1.0),
      period: Duration(seconds: 17),
    ),
    (
      color: TideColors.auroraIndigo,
      rect: Rect.fromLTWH(0.10, 0.63, 0.80, 0.45),
      from: (0.0, 0.0, 1.05),
      to: (-0.12, 0.06, 1.30),
      period: Duration(seconds: 15),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: RepaintBoundary(
          child: Opacity(
            opacity: opacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Degenerate constraints (a zero-size or unbounded slot)
                // would make the fractional geometry meaningless.
                if (!constraints.hasBoundedWidth ||
                    !constraints.hasBoundedHeight ||
                    constraints.maxWidth <= 0 ||
                    constraints.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                // The field overhangs the viewport (the design's
                // `inset: -20%`) so a blob can drift past an edge without
                // its own edge ever coming into view.
                return Transform.scale(
                  scale: 1.4,
                  child: Stack(
                    children: [
                      for (final b in _blobs)
                        Positioned(
                          left: w * b.rect.left,
                          top: h * b.rect.top,
                          width: w * b.rect.width,
                          height: h * b.rect.height,
                          child: _AuroraBlob(
                            color: b.color,
                            size: Size(w * b.rect.width, h * b.rect.height),
                            from: b.from,
                            to: b.to,
                            period: b.period,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Slow zoom-and-pan over hero artwork (the design's `kenburns`), so a still
/// cover never sits completely dead behind the title.
class TideKenBurns extends StatefulWidget {
  const TideKenBurns({super.key, required this.child});

  final Widget child;

  @override
  State<TideKenBurns> createState() => _TideKenBurnsState();
}

class _TideKenBurnsState extends State<TideKenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat(reverse: true);

  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, ui.lerpDouble(0, -10, _t.value)!),
        child: Transform.scale(
          scale: ui.lerpDouble(1.04, 1.14, _t.value)!,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// A specular sweep travelling across a surface — the design puts one on the
/// hero's Read button so the primary action reads as lit glass.
class TideSheen extends StatefulWidget {
  const TideSheen({super.key, required this.child});

  final Widget child;

  @override
  State<TideSheen> createState() => _TideSheenState();
}

class _TideSheenState extends State<TideSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => FractionalTranslation(
                  translation: Offset(
                    ui.lerpDouble(-1.2, 2.2, Curves.easeInOut
                        .transform(_c.value))!,
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.4,
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small outlined label — genres, and anything else that is a fact rather than
/// an action.
class TideTag extends StatelessWidget {
  const TideTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: TideColors.textAt(0.82)),
      ),
    );
  }
}

/// The one place the accent is allowed to fill a shape: a "New" marker, small
/// enough that it reads as a mark rather than a flood.
class TideBadge extends StatelessWidget {
  const TideBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TideColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          height: 1.4,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w500,
          color: TideColors.ground,
        ),
      ),
    );
  }
}

/// Circular glass control (back, search, and friends).
class TideIconButton extends StatelessWidget {
  const TideIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize = 17,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TideGlass(
        radius: size / 2,
        // No real blur: these sit over the aurora, which is diffuse colour —
        // blurring it looks identical to tinting it, and a BackdropFilter over
        // a continuously-animating background has to re-run its blur EVERY
        // frame. Blur is reserved for glass over actual artwork.
        blur: false,
        tintTop: 0.09,
        tintBottom: 0.03,
        highlight: 0.16,
        border: 0.11,
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: iconSize, color: TideColors.textAt(0.8)),
        ),
      ),
    );
  }
}

/// The kicker that heads a section: uppercase, widely tracked, quiet, with an
/// optional fact on the right and an optional destination behind the whole
/// strip. Tide separates groups with one of these rather than with a rule —
/// a divider says "these are different", a label says what they are.
class TideSectionHeader extends StatelessWidget {
  const TideSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(20, 30, 20, 12),
  });

  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label.toUpperCase(),
              style: TideText.kicker(size: 13, color: TideColors.textAt(0.5))
                  .copyWith(letterSpacing: 1.82),
            ),
            const Spacer(),
            if (trailing != null)
              Text(trailing!, style: TideText.caption(size: 12, opacity: 0.35)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 16, color: TideColors.textAt(0.35)),
            ],
          ],
        ),
      ),
    );
  }
}

/// One glass row: a destination, or a setting with its control on the right.
///
/// [lit] is for a row whose state is ON — the icon and the pane's edge take
/// the accent, so an active mode is visible from across the screen without
/// reading a single label.
class TideRow extends StatelessWidget {
  const TideRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.lit = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: 16,
      tintTop: lit ? 0.13 : 0.075,
      tintBottom: lit ? 0.05 : 0.026,
      highlight: lit ? 0.20 : 0.14,
      border: lit ? 0.20 : 0.09,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: tideEase,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: lit
                  ? TideColors.accent.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: lit
                    ? TideColors.accent.withValues(alpha: 0.32)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: lit ? TideColors.accent : TideColors.textAt(0.7),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// The chevron that marks a [TideRow] as leading somewhere.
class TideChevron extends StatelessWidget {
  const TideChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
        Icons.chevron_right,
        size: 18,
        color: TideColors.textAt(0.3),
      );
}

/// Switches between peer views: a glass pill with one lit segment that slides.
///
/// Replaces a Material TabBar, whose underline-and-ripple belongs to a
/// different design. The lit segment is the accent as an edge and a glow
/// around a pane, never as a filled block — a solid accent tab would be the
/// largest wash of colour in the app.
class TideSegmented extends StatelessWidget {
  const TideSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TideGlass(
        radius: 21,
        tintTop: 0.075,
        tintBottom: 0.026,
        highlight: 0.14,
        border: 0.09,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segment = constraints.maxWidth / labels.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: tideEase,
                  left: index * segment,
                  top: 0,
                  bottom: 0,
                  width: segment,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: TideColors.accent.withValues(alpha: 0.38),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: TideColors.accent.withValues(alpha: 0.22),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (i, label) in labels.indexed)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TideText.title(
                                size: 13.5,
                                color: i == index
                                    ? TideColors.textBright
                                    : TideColors.textAt(0.45),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tide's switch: a track that fills with the accent and lights when on.
///
/// Material's Switch carries its own colour scheme and ripple, both of which
/// fight the glass. This is the same control drawn in the design's terms —
/// and the accent filling a 46px track is small enough to stay a mark rather
/// than becoming a flood.
class TideSwitch extends StatelessWidget {
  const TideSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: tideEase,
        width: 46,
        height: 27,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? TideColors.accent
              : Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value
                ? TideColors.accent
                : Colors.white.withValues(alpha: 0.16),
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: TideColors.accent.withValues(alpha: 0.45),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: tideEase,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value
                  ? TideColors.ground
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// A manga cover, resolved through the same custom-cover / cache / per-source
/// header pipeline the rest of the app uses.
///
/// Falls back to a tinted gradient rather than an icon: in Tide a cover slot is
/// part of the composition, and an empty grey box with a glyph in it would read
/// as a hole. The tint is derived from the id so a given entry keeps the same
/// colour between sessions.
class TideCover extends ConsumerWidget {
  const TideCover({
    super.key,
    required this.manga,
    this.cacheWidth = 480,
    this.fit = BoxFit.cover,
  });

  final Manga manga;
  final int cacheWidth;
  final BoxFit fit;

  /// Deterministic two-stop gradient for a cover that has no artwork.
  static LinearGradient fallbackGradient(int seed) {
    const palette = <(Color, Color)>[
      (Color(0xFF3B3070), Color(0xFF191C2F)),
      (Color(0xFF1D3B57), Color(0xFF141A2C)),
      (Color(0xFF43305A), Color(0xFF1A1A2D)),
      (Color(0xFF2C4A44), Color(0xFF151D2A)),
      (Color(0xFF4A3A2C), Color(0xFF1D1A28)),
    ];
    final pair = palette[seed.abs() % palette.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [pair.$1, pair.$2],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: fallbackGradient(manga.id)),
    );
    final url =
        ref.watch(coverCacheProvider).coverUrlFor(manga.id, manga.thumbnailUrl);
    if (url == null || url.isEmpty) return fallback;
    final headers = ref
        .watch(installedSourceImageHeadersProvider)
        .valueOrNull?[manga.source];
    return SourceImage(
      url: url,
      headers: headers,
      cacheWidth: cacheWidth,
      fit: fit,
      placeholder: (_) => fallback,
      errorWidget: (_, _) => fallback,
    );
  }
}

/// Bottom-of-artwork scrim. The design layers the same four-stop fade under
/// every title that sits on a cover, so text stays legible without a slab
/// behind it.
class TideScrim extends StatelessWidget {
  const TideScrim({
    super.key,
    this.ground = TideColors.ground,
    this.opaqueTail = false,
  });

  final Color ground;

  /// End at the ground colour outright rather than at 94%. Set where the
  /// artwork has to hand off to page content: anything short of opaque leaves
  /// the join visible and text sitting on a ghost of the cover.
  final bool opaqueTail;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ground.withValues(alpha: opaqueTail ? 0.55 : 0.35),
              ground.withValues(alpha: opaqueTail ? 0.05 : 0.0),
              ground.withValues(alpha: opaqueTail ? 0.80 : 0.72),
              opaqueTail ? ground : ground.withValues(alpha: 0.94),
            ],
            stops: const [0.0, 0.30, 0.74, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Entry motion: content lifts and settles rather than appearing. One curve
/// (the design's `cubic-bezier(.22,1,.36,1)`) is used for every Tide
/// transition so the app moves consistently.
const tideEase = Cubic(0.22, 1, 0.36, 1);

class TideRise extends StatefulWidget {
  const TideRise({super.key, required this.child});

  final Widget child;

  @override
  State<TideRise> createState() => _TideRiseState();
}

class _TideRiseState extends State<TideRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: tideEase);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, ui.lerpDouble(14, 0, t.value)!),
          child: Transform.scale(
            scale: ui.lerpDouble(0.985, 1, t.value)!,
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

/// Time-of-day greeting for the home header. Purely cosmetic, but it is what
/// makes the screen feel like it belongs to the reader rather than to a
/// catalogue.
String tideGreeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 5) return 'Late';
  if (hour < 12) return 'Morning';
  if (hour < 17) return 'Afternoon';
  if (hour < 22) return 'Evening';
  return 'Tonight';
}

/// "4h ago" / "Yesterday" — the compact relative stamp the design uses in the
/// Tonight list.
String tideRelative(DateTime then, [DateTime? nowOverride]) {
  final now = nowOverride ?? DateTime.now();
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  final weeks = (d.inDays / 7).floor();
  if (weeks < 5) return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  final months = (d.inDays / 30).floor();
  return months <= 1 ? '1 month ago' : '$months months ago';
}

/// Chapter label in the design's voice: "Chapter 67", or the source's own name
/// when it carries more than the number.
String tideChapterLabel(String name, double number) {
  final trimmed = name.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (number < 0) return 'Chapter';
  final rounded = number.roundToDouble();
  final n = number == rounded
      ? rounded.toInt().toString()
      : number.toString().replaceFirst(RegExp(r'\.0+$'), '');
  return 'Chapter $n';
}

/// Presents [builder] as a Tide sheet: a glass panel that rises from the
/// bottom edge over a dimmed screen.
///
/// Tide's answer to `showDialog`. A Material dialog is a lit slab dropped in
/// the middle of the screen, which is the one gesture this design never makes;
/// and a decision belongs within reach of the thumb that asked for it.
Future<T?> showTideSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    elevation: 0,
    isScrollControlled: true,
    builder: builder,
  );
}

/// Confirm / cancel in a Tide sheet, with room for one extra control.
///
/// [extra] is handed the sheet's own `setState` so a caller can drive a
/// checkbox from a variable it owns — the pattern the history delete needs,
/// where the toggle changes which repository call runs.
class TideConfirmSheet extends StatefulWidget {
  const TideConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.extra,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Widget Function(void Function(VoidCallback) setState)? extra;

  @override
  State<TideConfirmSheet> createState() => _TideConfirmSheetState();
}

class _TideConfirmSheetState extends State<TideConfirmSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: TideGlass(
          radius: 26,
          // Genuinely floats over the screen it was called from, so the blur
          // has something to reveal.
          blur: true,
          tintTop: 0.13,
          tintBottom: 0.05,
          highlight: 0.26,
          border: 0.15,
          saturation: 1.9,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 44,
              offset: const Offset(0, 18),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: TideText.display(21)),
              const SizedBox(height: 10),
              Text(widget.message, style: TideText.body()),
              if (widget.extra != null) ...[
                const SizedBox(height: 18),
                widget.extra!(setState),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: widget.cancelLabel,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetButton(
                      label: widget.confirmLabel,
                      primary: true,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TideColors.accent,
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: TideColors.accent.withValues(alpha: 0.45),
                blurRadius: 24,
              ),
            ],
          ),
          child: Text(
            label,
            style: TideText.title(size: 14.5).copyWith(
              color: TideColors.ground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 46,
      child: TideGlass(
        radius: 23,
        tintTop: 0.09,
        tintBottom: 0.03,
        highlight: 0.16,
        border: 0.11,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TideText.title(size: 14.5, color: TideColors.textAt(0.8)),
          ),
        ),
      ),
    );
  }
}

/// Tide's checkbox: a rounded square that fills with the accent when set.
class TideCheck extends StatelessWidget {
  const TideCheck({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: tideEase,
            width: 21,
            height: 21,
            decoration: BoxDecoration(
              color: value ? TideColors.accent : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: value
                    ? TideColors.accent
                    : Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: value
                ? const Icon(Icons.check_rounded,
                    size: 14, color: TideColors.ground)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TideText.caption(size: 13, opacity: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress ring used on a chapter row that has been started but not finished.
class TideProgressRing extends StatelessWidget {
  const TideProgressRing({super.key, required this.progress, this.size = 26});

  /// 0–1.
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0, 1)),
        child: Center(
          child: Icon(
            Icons.play_arrow_rounded,
            size: size * 0.5,
            color: TideColors.accent,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2 - 0.75;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = TideColors.accent.withValues(alpha: 0.28),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = TideColors.accent.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
