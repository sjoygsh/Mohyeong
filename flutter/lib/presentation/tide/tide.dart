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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cover/cover_cache.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/source_icon.dart';
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

  /// Something went wrong, or is about to. A rose held at the accent's own
  /// lightness so a failure reads as a different hue rather than as a
  /// brighter, louder thing — Material's `error` red is the most saturated
  /// colour any screen would carry, and on this ground it shouts.
  ///
  /// This is a *label* colour, not a fill: the same rule the accent follows.
  static const danger = Color(0xFFEE8FA0);

  /// The one-pixel edge, for the few places a real rule is the only option —
  /// a swatch outline, or the flanking rules Mihon's missing-chapter row is
  /// made of. Tide separates groups with a [TideSectionHeader] rather than a
  /// divider, so reach for a label first and this second.
  static const hairline = Color(0x24FFFFFF); // white @ 14%

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

/// The corner scale.
///
/// The app had grown TWENTY-TWO distinct radii — 2, 4, 7, 8, 9, 10, 11, 14,
/// 15, 16, 18, 20, 21, 22, 23, 24, 26, 28, 29, 30, 32, 999 — which is not a
/// design, it is an accumulation. Nobody can tell 22 from 23, so the
/// difference carried no meaning while still costing a decision every time
/// something new got built.
///
/// Six steps and a pill, named for what they wrap rather than by t-shirt
/// size, because the question at a call site is "what am I drawing" and not
/// "how big should the corner be". The values are the modes of the clusters
/// that were already there, so almost nothing moves more than a pixel or two.
abstract final class TideRadius {
  /// Tiny marks: badges, library ticks, the smallest tags.
  static const tag = 8.0;

  /// Chips, segments, small controls.
  static const chip = 11.0;

  /// List rows and tiles — the most common shape in the app.
  static const row = 14.0;

  /// A pane of glass. [TideGlass]'s own default.
  static const pane = 16.0;

  /// Cards, covers, and the larger inset panels.
  static const panel = 21.0;

  /// Sheets and full-width panels — the biggest curves in the app.
  static const sheet = 28.0;

  /// Fully round. Anything using this wants a capsule, not a corner.
  static const pill = 999.0;
}

/// The one haptic in the app.
///
/// Deliberately narrow: it fires when a control CHANGES STATE under your
/// thumb — a switch, a checkbox, a chip, a segment, a tab — and nowhere else.
/// Not on navigation taps and not on buttons, because those already answer
/// visually with a whole new screen or a pressed state, and an app that
/// buzzes on every touch stops meaning anything by it.
///
/// `selectionClick` rather than an impact: these are selections, and it is
/// the lightest tick the platform offers.
void tideTick() => unawaited(HapticFeedback.selectionClick());

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
      // A Material ink splash would fight the glass, so this pane never had
      // one — but it had nothing in its place either, and a tappable pane
      // that does not move under your thumb is the difference between an app
      // that feels built and one that feels drawn. There are ~370 of these.
      pane = _TidePressable(onTap: onTap!, child: pane);
    }
    return pane;
  }
}

/// Press feedback for glass: the pane settles a little into the ground and
/// dims, then springs back.
///
/// Scale rather than a colour flash, because glass is a surface — the reading
/// is "you pushed it", not "it lit up". The numbers are small on purpose: at
/// row size anything past ~2% reads as the list flinching. Release runs
/// slower than press (the design's own `tideEase`), so it settles rather than
/// snapping, and a cancelled drag returns the same way.
class _TidePressable extends StatefulWidget {
  const _TidePressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TidePressable> createState() => _TidePressableState();
}

class _TidePressableState extends State<_TidePressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.982 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: tideEase,
        child: AnimatedOpacity(
          opacity: _down ? 0.78 : 1,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: tideEase,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The lit edge of [TideGlass], on something that paints its own surface.
///
/// Artwork in this design is never a bare rectangle sitting on the ground — it
/// is set into the same glass everything else is made of, so a cover picks up
/// the same top-lit bevel a panel does. Without it a grid of covers is a grid
/// of photographs, which is what every other reader looks like.
class TideEdge extends StatelessWidget {
  const TideEdge({
    super.key,
    required this.child,
    this.radius = 14,
    this.highlight = 0.22,
    this.border = 0.10,
  });

  final Widget child;
  final double radius;
  final double highlight;
  final double border;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GlassEdge(
        radius: radius,
        highlight: highlight,
        border: border,
      ),
      child: child,
    );
  }
}

/// Tide's "working on it": one accent arc travelling around a faint ring.
///
/// Material's [CircularProgressIndicator] draws a thick sweeping bar in its own
/// scheme's colour with its own easing — on a glass screen it is the most
/// obviously borrowed thing on it. This is the same idea in the design's terms,
/// and the same ring the chapter rows already use for progress.
///
/// Pass [value] and the arc stops travelling and simply fills, so a download
/// with a known length reads on the same ring as work of unknown length —
/// [TideProgressBar]'s circular twin, for a slot too small for a bar.
///
/// [color] exists for the reader, and only for the reader: page chrome sits on
/// whichever background the reader is set to (which can be white), so there it
/// takes the reader's own ink rather than the accent. Everywhere else the
/// default is the right answer.
class TideSpinner extends StatefulWidget {
  const TideSpinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 2,
    this.color,
    this.value,
  });

  final double size;
  final double strokeWidth;

  /// Overrides the accent. Null everywhere except the reader.
  final Color? color;

  /// 0–1 for a known length; null for indeterminate work, which travels.
  final double? value;

  @override
  State<TideSpinner> createState() => _TideSpinnerState();
}

class _TideSpinnerState extends State<TideSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _c.repeat();
  }

  @override
  void didUpdateWidget(TideSpinner old) {
    super.didUpdateWidget(old);
    // A determinate ring has nothing to animate — don't hold a ticker (and a
    // frame callback) open behind every download row in a chapter list.
    if ((widget.value == null) == (old.value == null)) return;
    if (widget.value == null) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? TideColors.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _SpinnerPainter(
              turn: _c.value,
              strokeWidth: widget.strokeWidth,
              color: color,
              value: widget.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({
    required this.turn,
    required this.strokeWidth,
    required this.color,
    required this.value,
  });

  final double turn;
  final double strokeWidth;
  final Color color;
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - strokeWidth / 2;
    final centre = (Offset.zero & size).center;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: 0.16),
    );
    final progress = value;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      // Determinate fills from twelve o'clock; indeterminate starts there and
      // travels.
      (progress == null ? turn * 2 * math.pi : 0) - math.pi / 2,
      progress == null
          // Just under a third of the ring: long enough to read as motion,
          // short enough that the gap never closes into a plain circle.
          ? 2 * math.pi * 0.3
          : 2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.turn != turn || old.value != value || old.color != color;
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
  const TideAurora({super.key, this.opacity = TideAuroraLevel.hero});

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

/// A selectable option. Off it reads as [TideTag]; on, it takes the accent as
/// an edge and a wash — never as a fill, which at chip size would put a solid
/// block of colour into every filter row.
class TideChip extends StatelessWidget {
  const TideChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tint =
        selected ? TideColors.accentLight : TideColors.textAt(0.75);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tideTick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: tideEase,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? TideColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? TideColors.accent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(fontSize: 12, color: tint)),
          ],
        ),
      ),
    );
  }
}

/// "Already yours" marker for a cover in a browse result. Mirrors Mihon's
/// in-library badge, in the one place the accent is allowed to fill a shape —
/// small enough that it reads as a mark.
class TideLibraryMark extends StatelessWidget {
  const TideLibraryMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TideColors.accent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: TideColors.accent.withValues(alpha: 0.5),
            blurRadius: 12,
          ),
        ],
      ),
      child: const Icon(
        Icons.collections_bookmark,
        size: 13,
        color: TideColors.ground,
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
    this.leading,
    this.trailing,
    this.onTap,
    this.lit = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Takes the icon tile's place. For a row that stands for something with a
  /// face of its own — a source and its logo — where a glyph would be the
  /// same shape on every line.
  final Widget? leading;

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
          if (leading != null)
            SizedBox(width: 36, height: 36, child: Center(child: leading))
          else
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

/// The app's navigation: one floating glass bar, over every tab.
///
/// It lives in the shell rather than on a screen, because a bar that appears
/// on one page and is replaced by a Material one on the next is the single
/// loudest way an app can look like two apps.
///
/// Icon SHAPES are the app's existing ones, not the design's generic
/// home/book/search/person set — these destinations do specific things, and a
/// magnifier standing in for Browse or a person for More reads wrong the
/// moment you tap it. The glass is the design; the glyphs are the app's.
class TideTabBar extends StatelessWidget {
  const TideTabBar({
    super.key,
    required this.activeTab,
    required this.onSelect,
    required this.onLibrary,
  });

  /// 0 Home · 1 History · 2 Browse · 3 More.
  final int activeTab;
  final ValueChanged<int> onSelect;

  /// The library grid is a pushed route rather than a tab, so its slot never
  /// reads as active.
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: TideGlass(
        radius: 29,
        // The bar genuinely floats over scrolling covers, so there is
        // something behind it worth blurring.
        blur: true,
        tintTop: 0.13,
        tintBottom: 0.05,
        highlight: 0.26,
        border: 0.15,
        saturation: 1.9,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Outlined throughout. The bar had `Icons.home` filled next to
            // four outlined peers — the single most-looked-at row in the app
            // and it was the one that gave the family away.
            _TabIcon(
              icon: Icons.home_outlined,
              active: activeTab == 0,
              onTap: () => onSelect(0),
            ),
            _TabIcon(
              icon: Icons.collections_bookmark_outlined,
              onTap: onLibrary,
            ),
            _TabIcon(
              icon: Icons.history_outlined,
              active: activeTab == 1,
              onTap: () => onSelect(1),
            ),
            _TabIcon(
              icon: Icons.explore_outlined,
              active: activeTab == 2,
              onTap: () => onSelect(2),
            ),
            _TabIcon(
              icon: Icons.more_horiz,
              active: activeTab == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, this.active = false, this.onTap});

  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              // Not when you re-tap the tab you are on: that is the
              // scroll-to-top / open-search gesture, not a destination change.
              if (!active) tideTick();
              onTap!();
            },
      child: SizedBox(
        width: 52,
        height: 58,
        child: Icon(
          icon,
          size: 22,
          color: active ? TideColors.accentLight : TideColors.textAt(0.5),
        ),
      ),
    );
  }
}

/// Height a tab's scrollable must leave clear at its foot so the floating bar
/// never covers its last row.
const double tideBarInset = 110;

/// How much aurora a screen carries.
///
/// The light behind the glass is the design's ground, and it was being dialled
/// in per screen — five different values across the app, none of them chosen
/// against the others. It is one decision with three answers, and the answer
/// follows from how much ground the screen actually shows.
abstract final class TideAuroraLevel {
  /// Screens built around artwork, where the ground is most of what you see.
  static const hero = 0.72;

  /// Ordinary list and grid pages: enough that the ground is lit, not so much
  /// that it competes with the rows sitting on it.
  static const page = 0.5;

  /// Screens that are wall-to-wall content — long settings runs, dense feeds —
  /// where the aurora is a hint at the edges rather than a wash.
  static const dense = 0.32;
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
                          // Only when the segment actually moves — re-tapping
                          // the one you are on changes nothing to feel.
                          onTap: () {
                            if (i != index) tideTick();
                            onChanged(i);
                          },
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
      onTap: () {
        tideTick();
        onChanged(!value);
      },
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

/// A source's own mark, on a tile of glass.
///
/// Sources are websites, and every website publishes a logo — so a browse row
/// wears the real one rather than a generic glyph. The mark is resolved once
/// per source and painted from a local file after that; until it lands (and
/// forever, for a site that publishes nothing usable) the row falls back to
/// [TideSigil], so a list is never a column of empty tiles.
class TideSourceLogo extends ConsumerWidget {
  const TideSourceLogo({
    super.key,
    required this.seed,
    required this.label,
    this.baseUrl,
    this.userAgent,
    this.size = 38,
    this.radius = 11,
  });

  /// Stable identity for the fallback's colour — the extension id.
  final String seed;

  /// The source's name; its initial is the fallback's glyph.
  final String label;

  /// The site to ask. Null or empty (Local source, a manifest with no
  /// `base_url`) skips the lookup entirely and stays on the sigil.
  final String? baseUrl;

  /// Manifest `user_agent`, for the hosts that reject the browser one.
  final String? userAgent;

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = TideSigil(
      seed: seed,
      label: label,
      size: size,
      radius: radius,
    );
    final base = baseUrl;
    if (base == null || base.isEmpty) return fallback;

    final path = ref
        .watch(sourceIconProvider((
          id: seed,
          baseUrl: base,
          userAgent: userAgent,
        )))
        .valueOrNull;
    if (path == null || path.isEmpty) return fallback;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        // A favicon is drawn to its own edges; inset so it reads as a mark on
        // a tile rather than as a full-bleed square fighting the row's radius.
        padding: EdgeInsets.all(size * 0.16),
        child: SourceImage(
          url: path,
          fit: BoxFit.contain,
          placeholder: (_) => const SizedBox.shrink(),
          errorWidget: (_, _) => Center(
            child: Text(
              _initialOf(label),
              style: TextStyle(
                fontSize: size * 0.42,
                height: 1,
                fontWeight: FontWeight.w500,
                color: TideColors.brightAt(0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The source's initial over a gradient derived from its id — the mark for a
/// source that has none of its own. Deterministic, so a given source keeps the
/// same colour between sessions and stays findable by shape.
class TideSigil extends StatelessWidget {
  const TideSigil({
    super.key,
    required this.seed,
    required this.label,
    this.size = 38,
    this.radius = 11,
  });

  final String seed;
  final String label;
  final double size;
  final double radius;

  /// Stable across sessions and platforms — String.hashCode is not something
  /// to lean on for anything the user would notice changing.
  static int seedOf(String s) {
    var sum = 0;
    for (final unit in s.codeUnits) {
      sum = (sum * 31 + unit) & 0x7fffffff;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: TideCover.fallbackGradient(seedOf(seed)),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        _initialOf(label),
        style: TextStyle(
          fontSize: size * 0.42,
          height: 1,
          fontWeight: FontWeight.w500,
          color: TideColors.brightAt(0.9),
        ),
      ),
    );
  }
}

String _initialOf(String label) {
  final trimmed = label.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

/// `https://www.asuracomic.net/` → `asuracomic.net`. What a source row says
/// under the name: "EN" on its own was a two-letter subtitle on an empty line,
/// and the domain is the thing that actually distinguishes two sources with
/// near-identical names.
String? tideSourceHost(String? baseUrl) {
  if (baseUrl == null || baseUrl.isEmpty) return null;
  final host = Uri.tryParse(baseUrl)?.host;
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
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

/// The fade that grows in behind floating chrome once the artwork it was
/// resting on has scrolled away.
///
/// A back control over a cover reads fine — the scrim under the title is
/// already holding that corner down. Fifteen hundred pixels later the same
/// control is sitting on body text, and a translucent pane over prose is just
/// unreadable prose. So the ground comes up to meet it.
class TideTopScrim extends StatelessWidget {
  const TideTopScrim({super.key, required this.opacity});

  /// 0 while the chrome is still over artwork, 1 once it is over content.
  final double opacity;

  /// How far a screen scrolls before the scrim is fully in. Callers pass
  /// their own start point — it is the height of their artwork.
  static double progressFor(double pixels, {required double coverHeight}) =>
      ((pixels - (coverHeight - 150)) / 90).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Container(
          // Tall enough to clear a 42px control at top+8 and still have room
          // left to fade out in, so the scrim never ends on a hard line.
          height: MediaQuery.paddingOf(context).top + 96,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                TideColors.ground,
                TideColors.ground,
                TideColors.ground.withValues(alpha: 0.82),
                TideColors.ground.withValues(alpha: 0),
              ],
              stops: const [0, 0.42, 0.66, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// The head of a pushed screen: a back control, a title, and any actions.
///
/// Tide has no app bars. A screen you pushed into needs a way out and a name,
/// and nothing else — the bar that used to carry those was mostly a coloured
/// slab holding two icons apart.
class TideHeader extends StatelessWidget {
  const TideHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;

  /// What the screen is about, when the title alone doesn't say — the series
  /// a notes editor belongs to, the URL a webview is showing.
  final String? subtitle;

  final List<Widget> actions;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        20,
        12,
      ),
      child: Row(
        children: [
          TideIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 15,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                    color: TideColors.text,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.caption(size: 11.5, opacity: 0.45),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) const SizedBox(width: 8),
          ...actions,
        ],
      ),
    );
  }
}

/// The shell every Tide sheet is built in: glass, blurred, safe-area aware,
/// and lifted clear of the keyboard when one is up.
class TideSheetPanel extends StatelessWidget {
  const TideSheetPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A pill button in a sheet. [primary] fills with the accent; otherwise it is
/// another pane of glass.
class TideButton extends StatelessWidget {
  const TideButton({
    super.key,
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
            style: TideText.title(size: 14.5)
                .copyWith(color: TideColors.ground),
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

/// A single-line text field on a pane of glass.
///
/// Tide has no outlined inputs: a Material `OutlineInputBorder` draws a hard
/// rectangle with a notched label, which is a different design's idea of
/// where a field begins. Here the pane is the field, and the label sits above
/// it rather than cutting through its edge.
class TideField extends StatelessWidget {
  const TideField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.icon,
    this.obscureText = false,
    this.autofocus = false,
    this.autocorrect = true,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;

  /// Drawn above the pane, in the same kicker the section headers use.
  final String? label;
  final String? hintText;
  final IconData? icon;
  final bool obscureText;
  final bool autofocus;
  final bool autocorrect;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final field = SizedBox(
      height: 46,
      child: TideGlass(
        radius: 23,
        tintTop: 0.09,
        tintBottom: 0.03,
        highlight: 0.16,
        border: 0.11,
        padding: EdgeInsets.only(left: icon != null ? 14 : 17, right: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: TideColors.textAt(0.45)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                autofocus: autofocus,
                autocorrect: autocorrect,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                cursorColor: TideColors.accent,
                style: TideText.title(size: 14.5),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  hintStyle: TideText.title(
                    size: 14.5,
                    color: TideColors.textAt(0.33),
                  ),
                ),
              ),
            ),
            ?trailing,
            if (trailing == null) const SizedBox(width: 9),
          ],
        ),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            label!.toUpperCase(),
            style: TideText.kicker(size: 11, color: TideColors.textAt(0.45))
                .copyWith(letterSpacing: 1.6),
          ),
        ),
        field,
      ],
    );
  }
}

/// Asks for one line of text and pops it. Pops null on cancel.
class TideInputSheet extends StatefulWidget {
  const TideInputSheet({
    super.key,
    required this.title,
    this.initialValue = '',
    this.hintText,
    this.confirmLabel = 'Save',
    this.keyboardType,
  });

  final String title;
  final String initialValue;
  final String? hintText;
  final String confirmLabel;
  final TextInputType? keyboardType;

  @override
  State<TideInputSheet> createState() => _TideInputSheetState();
}

class _TideInputSheetState extends State<TideInputSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: TideText.display(21)),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: TideGlass(
              radius: 22,
              tintTop: 0.09,
              tintBottom: 0.03,
              highlight: 0.16,
              border: 0.11,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  cursorColor: TideColors.accent,
                  style: TideText.title(size: 14.5),
                  keyboardType: widget.keyboardType,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: TideText.title(
                      size: 14.5,
                      color: TideColors.textAt(0.33),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TideButton(
                  label: widget.confirmLabel,
                  primary: true,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Picks one of a set of values and pops it. Pops null when dismissed.
class TideOptionSheet extends StatelessWidget {
  const TideOptionSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;

  /// `(value, label)` pairs, in the order the source declared them.
  final List<(String, String)> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TideText.display(21)),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, (value, label)) in options.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _Option(
                      label: label,
                      selected: value == selected,
                      onTap: () => Navigator.of(context).pop(value),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: 14,
      tintTop: selected ? 0.13 : 0.06,
      tintBottom: selected ? 0.05 : 0.02,
      highlight: selected ? 0.20 : 0.12,
      border: selected ? 0.20 : 0.08,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TideText.title(
                color: selected ? TideColors.textBright : TideColors.text,
              ),
            ),
          ),
          if (selected)
            const Icon(Icons.check_rounded,
                size: 18, color: TideColors.accent),
        ],
      ),
    );
  }
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
      onTap: () {
        tideTick();
        onChanged(!value);
      },
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

/// Nothing to show, said properly.
///
/// Four screens had grown their own private copy of this — `_EmptyPanel`,
/// `_EmptyCard`, and two inline ones — at radius 26/28, display 21/23/24 and
/// four different paddings, while two other screens said nothing but a bare
/// unstyled `Text`. An empty screen is the one a new user sees FIRST and the
/// one a search dead-ends on, so it is worth having exactly one of.
///
/// Type only, no illustration: Tide's ground and glass already carry the mood,
/// and a spot drawing would be the only illustration in the app.
///
/// [action] is for the empty states that can offer a way out — an empty
/// library should point at Browse rather than just stating the obvious.
class TideEmpty extends StatelessWidget {
  const TideEmpty({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TideGlass(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TideText.display(22),
              ),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TideText.body(),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: 190,
                  child: TideButton(
                    label: actionLabel!,
                    primary: true,
                    onTap: onAction!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tide's transient message — the app's answer to a SnackBar.
///
/// Material's SnackBar is a squared-off slab in its own scheme's colour, with
/// its own type and its own slide, docked to the very bottom edge where this
/// app's floating navigation already lives. It was the single most-used
/// unthemed thing in the app: fifty-odd sites, every one of them announcing a
/// result in another design's voice.
///
/// This is the same job done in Tide's terms — a pane of glass that rises just
/// above the tab bar, holds, and fades.
///
/// It is obtained rather than called on purpose. Almost every message in this
/// app is reported AFTER an await, and reaching for a BuildContext across an
/// async gap is the bug that pattern invites. [TideToast.of] captures the
/// overlay up front, exactly the way the old code captured a
/// `ScaffoldMessenger`, and stays safe to call once the await returns.
class TideToast {
  const TideToast._(this._overlay);

  final OverlayState _overlay;

  /// Captures the overlay for later. Call this BEFORE the await, then
  /// [show] after it.
  static TideToast of(BuildContext context) =>
      TideToast._(Overlay.of(context, rootOverlay: true));

  /// Clearance for the floating navigation: the bar sits at bottom 26 and is
  /// 58 tall, so this lands a toast just above it. On a pushed screen with no
  /// bar it simply floats a little higher than the edge, which is where a
  /// message belongs anyway.
  static const _bottomInset = 96.0;

  /// Rise and fade, either side of the dwell.
  static const _riseMs = 320;
  static const _fadeMs = 260;

  static OverlayEntry? _current;

  /// Shows [message]. A second call replaces the first rather than stacking —
  /// two messages on screen at once is never what the caller meant, and it is
  /// why none of the call sites need an equivalent of `hideCurrentSnackBar`.
  ///
  /// [duration] overrides the default dwell for the few messages that were
  /// given an explicit one as SnackBars.
  void show(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    if (message.isEmpty || !_overlay.mounted) return;
    _dismiss();
    // Dwell: long enough to read a sentence, and longer when there is
    // something to tap — mirrors the SnackBar durations this replaces.
    final dwell =
        duration ?? Duration(milliseconds: actionLabel == null ? 3200 : 5000);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TideToastHost(
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        lifetime: Duration(milliseconds: _riseMs + _fadeMs) + dwell,
        onFinished: () => _remove(entry),
      ),
    );
    _current = entry;
    _overlay.insert(entry);
  }

  /// Takes [entry] away, if it is still the one on screen.
  ///
  /// The guard matters: a toast that has been REPLACED still runs its last
  /// frames out before its host is disposed, and without this the old one's
  /// finish would take the new one down with it.
  static void _remove(OverlayEntry entry) {
    if (_current == entry) _current = null;
    if (entry.mounted) entry.remove();
  }

  static void _dismiss() {
    final entry = _current;
    if (entry != null) _remove(entry);
  }

  /// Drops any toast on screen. For a screen going away under one.
  static void clear() => _dismiss();
}

class _TideToastHost extends StatefulWidget {
  const _TideToastHost({
    required this.message,
    required this.lifetime,
    required this.onFinished,
    this.actionLabel,
    this.onAction,
  });

  final String message;

  /// Rise, dwell and fade, end to end.
  final Duration lifetime;

  /// Called once the fade has finished, to take the overlay entry away.
  final VoidCallback onFinished;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_TideToastHost> createState() => _TideToastHostState();
}

/// The toast's whole life is one [AnimationController] rather than a rise plus
/// a `Timer` for the dwell.
///
/// A bare Timer outlives the tree it belongs to: it kept firing after the
/// screen was gone, held the overlay entry alive in its closure, and made every
/// widget test that happened to trigger a message fail with "a Timer is still
/// pending even after the widget tree was disposed". A controller is owned by
/// this State and dies with it.
class _TideToastHostState extends State<_TideToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.lifetime,
  )
    ..addStatusListener(_onStatus)
    ..forward();

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // Removing an OverlayEntry re-parents the overlay's children, so it must
    // not happen inside the animation tick that is mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFinished());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Opacity over the whole lifetime: in over [_riseMs], hold, out over
  /// [_fadeMs].
  double _opacityAt(double v) {
    final total = widget.lifetime.inMilliseconds;
    final riseEnd = TideToast._riseMs / total;
    final fadeStart = (total - TideToast._fadeMs) / total;
    if (v <= riseEnd) return (v / riseEnd).clamp(0.0, 1.0);
    if (v >= fadeStart) {
      return (1 - (v - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
    }
    return 1;
  }

  /// The rise is only the entry; once up, it stays put.
  double _offsetAt(double v) {
    final riseEnd = TideToast._riseMs / widget.lifetime.inMilliseconds;
    if (v >= riseEnd) return 0;
    return ui.lerpDouble(18, 0, tideEase.transform((v / riseEnd).clamp(0, 1)))!;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + TideToast._bottomInset,
      child: IgnorePointer(
        ignoring: widget.onAction == null,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Opacity(
            opacity: _opacityAt(_c.value),
            child: Transform.translate(
              offset: Offset(0, _offsetAt(_c.value)),
              child: child,
            ),
          ),
          child: TideGlass(
            radius: 22,
            // Genuinely over content, so the blur has something to reveal.
            blur: true,
            tintTop: 0.14,
            tintBottom: 0.05,
            highlight: 0.28,
            border: 0.16,
            saturation: 1.9,
            padding: EdgeInsets.fromLTRB(
              18,
              13,
              widget.actionLabel == null ? 18 : 8,
              13,
            ),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    widget.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.title(size: 13.5),
                  ),
                ),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      TideToast._dismiss();
                      widget.onAction?.call();
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text(
                        widget.actionLabel!.toUpperCase(),
                        style: TideText.kicker(
                          size: 11,
                          color: TideColors.accent,
                        ).copyWith(letterSpacing: 1.4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A determinate bar, for the few places something has a known length: cache
/// size against its cap, a download's progress, a batch migration.
///
/// Material's LinearProgressIndicator is a square-ended bar in the scheme's
/// colour; this is the same reading as a lit track in the design's.
class TideProgressBar extends StatelessWidget {
  const TideProgressBar({super.key, required this.value, this.height = 5});

  /// 0–1, or null for indeterminate work of unknown length.
  final double? value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
            if (value != null)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value!.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: TideColors.accent,
                    boxShadow: [
                      BoxShadow(
                        color: TideColors.accent.withValues(alpha: 0.45),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              )
            else
              const _IndeterminateSweep(),
          ],
        ),
      ),
    );
  }
}

/// The travelling band an indeterminate [TideProgressBar] shows.
class _IndeterminateSweep extends StatefulWidget {
  const _IndeterminateSweep();

  @override
  State<_IndeterminateSweep> createState() => _IndeterminateSweepState();
}

class _IndeterminateSweepState extends State<_IndeterminateSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(ui.lerpDouble(-0.45, 1.0, _c.value)!, 0),
        child: child,
      ),
      child: FractionallySizedBox(
        widthFactor: 0.45,
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                TideColors.accent.withValues(alpha: 0),
                TideColors.accent,
                TideColors.accent.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pull-to-refresh in Tide's terms.
///
/// This one WRAPS Material's [RefreshIndicator] instead of replacing it, and
/// that is a deliberate exception to the rule the rest of this file follows.
/// The visual is trivial; the machinery is not — overscroll behaves differently
/// under each platform's scroll physics, and drag cancellation, the settle
/// animation and nested scrollables are several hundred lines of edge cases in
/// the framework. Reimplementing that for a pull affordance would trade a real
/// risk of breaking refresh against a small visual gain, which is a bad trade.
///
/// What it does remove is the part that actually looked borrowed: the Material
/// puck. No elevation, no surface, no slab — just the accent arc on the
/// ground, which is the same mark [TideSpinner] draws.
class TideRefresh extends StatelessWidget {
  const TideRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: TideColors.accent,
      backgroundColor: Colors.transparent,
      elevation: 0,
      strokeWidth: 2,
      // The design's own curve, so a pull settles the way everything else in
      // the app moves.
      displacement: 46,
      child: child,
    );
  }
}
