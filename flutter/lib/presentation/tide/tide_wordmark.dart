import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tide.dart';

/// The app's name, written on rather than shown.
///
/// This replaces the launcher roundel that used to sit on the launch screen.
/// A logo dropped whole onto a flat panel is the one moment the app looks
/// like a file someone pasted; a word being written is the app introducing
/// itself in its own hand.
///
/// The reveal is a mask, not a wipe. The glyphs are painted once, then kept
/// only where a set of brush passes have already crossed them
/// ([BlendMode.dstIn]), so the word emerges under the strokes instead of
/// sliding in from an edge. Each pass is drawn as three slightly offset
/// bristles of differing width and alpha, which is what keeps the leading
/// edge ragged — a single round-capped line reads as a highlighter.
class TideWordmark extends StatelessWidget {
  const TideWordmark({
    super.key,
    required this.progress,
    this.text = 'Mohyeong',
    this.size = 42,
  });

  /// 0 → nothing written, 1 → the whole word.
  final double progress;

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BrushWordPainter(
        progress: progress,
        text: text,
        fontSize: size,
        style: TideText.display(size),
      ),
      // Enough room for the descender and the glow the leading edge throws.
      size: Size(size * text.length * 0.62, size * 1.7),
    );
  }
}

class _BrushWordPainter extends CustomPainter {
  _BrushWordPainter({
    required this.progress,
    required this.text,
    required this.fontSize,
    required this.style,
  });

  final double progress;
  final String text;
  final double fontSize;
  final TextStyle style;

  /// The three passes, as (start, duration) on the 0..1 timeline plus the
  /// band's centre as a fraction of the word's height. They overlap in time
  /// so the hand never appears to stop between strokes.
  static const _passes = <({double start, double span, double y})>[
    (start: 0.00, span: 0.62, y: 0.30),
    (start: 0.16, span: 0.62, y: 0.58),
    (start: 0.32, span: 0.62, y: 0.84),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final origin = Offset(
      (size.width - painter.width) / 2,
      (size.height - painter.height) / 2,
    );
    final band = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      painter.width,
      painter.height,
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    painter.paint(canvas, origin);

    // Keep the glyphs only where a bristle has already passed.
    final mask = Paint()
      ..blendMode = BlendMode.dstIn
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final pass in _passes) {
      final t = _passProgress(pass.start, pass.span);
      if (t <= 0) continue;
      _paintBristles(canvas, band, pass.y, t, mask);
    }
    canvas.restore();

    // Wet ink at the leading edge: the accent as a glow, never a fill.
    if (progress > 0.02 && progress < 0.99) {
      final head = band.left + band.width * Curves.easeOut.transform(progress);
      canvas.drawCircle(
        Offset(head, band.center.dy),
        fontSize * 0.42,
        Paint()
          ..color = TideColors.accent.withValues(alpha: 0.30 * (1 - progress))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.5),
      );
    }

    // The rule under the word draws itself last, once the writing is done.
    final ruleT = _passProgress(0.72, 0.28);
    if (ruleT > 0) {
      final y = band.bottom + fontSize * 0.30;
      final half = band.width * 0.5 * Curves.easeOutCubic.transform(ruleT);
      canvas.drawLine(
        Offset(band.center.dx - half, y),
        Offset(band.center.dx + half, y),
        Paint()
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            Offset(band.center.dx - half, y),
            Offset(band.center.dx + half, y),
            [
              TideColors.accent.withValues(alpha: 0),
              TideColors.accent.withValues(alpha: 0.85),
              TideColors.accent.withValues(alpha: 0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
    }
  }

  /// One pass, drawn as three bristles. The middle one carries the pass; the
  /// outer two are thinner, shorter-lived and partly transparent, which is
  /// what frays the edge the eye reads as hair rather than rubber.
  void _paintBristles(
    Canvas canvas,
    Rect band,
    double yFraction,
    double t,
    Paint mask,
  ) {
    final eased = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
    final baseY = band.top + band.height * yFraction;
    // Overshoot the word on both sides: a stroke that starts and stops exactly
    // on the glyphs looks measured, and a brush never is.
    final x0 = band.left - fontSize * 0.34;
    final x1 = band.right + fontSize * 0.34;

    const bristles = <({double dy, double width, double alpha, double lead})>[
      (dy: -0.20, width: 0.30, alpha: 0.55, lead: 0.94),
      (dy: 0.00, width: 0.52, alpha: 1.00, lead: 1.00),
      (dy: 0.22, width: 0.26, alpha: 0.45, lead: 0.88),
    ];

    for (final b in bristles) {
      final end = x0 + (x1 - x0) * (eased * b.lead).clamp(0.0, 1.0);
      if (end <= x0) continue;
      final y = baseY + fontSize * b.dy * 0.34;
      // A shallow arc rather than a rule — the wrist pivots.
      final path = Path()
        ..moveTo(x0, y + fontSize * 0.05)
        ..quadraticBezierTo(
          (x0 + end) / 2,
          y - fontSize * 0.06,
          end,
          y + fontSize * 0.02,
        );
      mask
        ..strokeWidth = fontSize * b.width
        ..color = Color.fromRGBO(255, 255, 255, b.alpha);
      canvas.drawPath(path, mask);
    }
  }

  /// Maps the global 0..1 [progress] onto one element's own window.
  double _passProgress(double start, double span) =>
      ((progress - start) / span).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(_BrushWordPainter old) =>
      old.progress != progress || old.text != text || old.style != style;
}

/// Plays [TideWordmark] over the app once per process, then hands over.
///
/// The platform launch screen is now nothing but Tide's ground — no icon (see
/// `launch_background.xml` and `values-v31/styles.xml`) — so this is what
/// covers the gap between the window appearing and the first tab being ready.
/// It is deliberately short: the child is built and running underneath the
/// whole time, so this only ever hides work that was happening anyway.
class TideSplashGate extends StatefulWidget {
  const TideSplashGate({super.key, required this.child});

  final Widget child;

  /// Cold start only. A rebuild of the app root — a theme change, a hot
  /// reload — must not replay the introduction.
  static bool _played = false;

  /// False only while the introduction is actually on screen.
  ///
  /// Deliberately starts TRUE: a widget test that builds a screen without the
  /// gate, or any launch where the intro is skipped, must not sit waiting for
  /// something that will never happen.
  static final ValueNotifier<bool> introDone = ValueNotifier<bool>(true);

  /// Runs [action] once the introduction is off the screen, or immediately if
  /// it is not playing.
  ///
  /// Startup work that would otherwise land mid-animation uses this. The
  /// animation and the first-build storm were measured fighting on the same
  /// isolate: two ~1s main-thread stalls (63 and 62 skipped frames) inside the
  /// intro's own window, which is what made the word appear frozen.
  static void whenIntroDone(VoidCallback action) {
    if (introDone.value) {
      action();
      return;
    }
    void listener() {
      if (!introDone.value) return;
      introDone.removeListener(listener);
      action();
    }
    introDone.addListener(listener);
  }

  @override
  State<TideSplashGate> createState() => _TideSplashGateState();
}

class _TideSplashGateState extends State<TideSplashGate>
    with SingleTickerProviderStateMixin {
  // The write is the cheap part; the HOLD is what makes it register. A debug
  // engine takes ~3.8s to first paint, so by the time the word starts you have
  // been looking at bare ground for four seconds — a word that then appears
  // and leaves inside 1.6s is genuinely easy to miss, which is exactly what
  // happened. Verified with a logged initState: the gate always fires, it was
  // only ever too brief to notice. Release paints far sooner, so this is a
  // ceiling rather than a typical wait.
  static const _write = Duration(milliseconds: 1150);
  static const _hold = Duration(milliseconds: 900);
  static const _fade = Duration(milliseconds: 420);

  late final AnimationController _c;
  late final Animation<double> _stroke;
  late final Animation<double> _veil;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _done = TideSplashGate._played;
    final total = _write + _hold + _fade;
    _c = AnimationController(vsync: this, duration: total);
    final writeEnd = _write.inMilliseconds / total.inMilliseconds;
    final fadeStart =
        (_write + _hold).inMilliseconds / total.inMilliseconds;
    _stroke = CurvedAnimation(
      parent: _c,
      curve: Interval(0, writeEnd, curve: Curves.linear),
    );
    _veil = CurvedAnimation(
      parent: _c,
      curve: Interval(fadeStart, 1, curve: tideEase),
    );
    if (!_done) {
      TideSplashGate._played = true;
      TideSplashGate.introDone.value = false;
      _c.forward().whenComplete(() {
        // Released even if this State was disposed mid-animation — anything
        // parked on `whenIntroDone` would otherwise never run at all.
        TideSplashGate.introDone.value = true;
        if (mounted) setState(() => _done = true);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The child stays in slot 0 of the same Stack for the life of the app,
    // finished or not. Returning `widget.child` bare once the animation ended
    // moved it to a different position in the element tree, which remounts the
    // ENTIRE app a second and a half into every cold start: HomeScreen's State
    // is rebuilt from scratch, so its tab pre-warm set empties and restarts,
    // and anything else holding screen state loses it. Only the veil comes and
    // goes; one idle Stack is the whole cost of keeping that from happening.
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (!_done)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => IgnorePointer(
                child: Opacity(
                  opacity: 1 - _veil.value,
                  child: _veilLayer(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _veilLayer() {
    return ColoredBox(
      color: TideColors.ground,
      child: Stack(
        children: [
          const Positioned.fill(child: TideAurora()),
          Center(
            child: TideGlass(
              radius: TideRadius.panel,
              padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TideWordmark(progress: _stroke.value, size: 46),
                  const SizedBox(height: 10),
                  // The Korean the roundel used to carry, kept as a kicker so
                  // dropping the logo does not drop the identity with it.
                  Opacity(
                    opacity: math.max(0, (_stroke.value - 0.72) / 0.28),
                    child: Text(
                      '모형',
                      style: TideText.kicker(
                        size: 11,
                        color: TideColors.textAt(0.42),
                      ).copyWith(letterSpacing: 5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
