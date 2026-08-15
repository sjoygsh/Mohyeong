import 'package:flutter/material.dart';

import 'tide.dart';

/// The app's name, set plainly.
///
/// This used to write itself on: the glyphs were painted once and then kept
/// only where a set of offset brush bristles had crossed them
/// ([BlendMode.dstIn]), with a glow at the leading edge and a rule that drew
/// itself afterwards. It was the most conspicuous thing in the app and it sat
/// in front of every cold start, so it went — a launch screen's job is to be
/// forgotten. The word is simply typeset now; only the veil around it moves.
class TideWordmark extends StatelessWidget {
  const TideWordmark({
    super.key,
    this.text = 'Mohyeong',
    this.size = 42,
  });

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TideText.display(size));
  }
}

/// Covers the gap between the window appearing and the first tab being ready.
///
/// The platform launch screen is nothing but Tide's ground — no icon (see
/// `launch_background.xml` and `values-v31/styles.xml`) — so this is what fills
/// that gap. It is deliberately short: the child is built and running
/// underneath the whole time, so this only ever hides work that was happening
/// anyway.
class TideSplashGate extends StatefulWidget {
  const TideSplashGate({super.key, required this.child});

  final Widget child;

  /// Cold start only. A rebuild of the app root — a theme change, a hot
  /// reload — must not replay it.
  ///
  /// There is deliberately no hook for deferring startup work until this
  /// finishes. One existed briefly, because a debug build stalls the main
  /// thread twice for ~1s during cold start and the animation visibly jumps.
  /// An A/B on RELEASE settled it: three cold starts each, with the deferral
  /// and without, and zero skipped frames either way. The stalls are debug JIT
  /// compiling the widget tree, which no amount of scheduling removes, so the
  /// hook was buying nothing in the shipping build and delaying the tab
  /// pre-warm by the length of the intro. Measure in release before adding it
  /// back.
  static bool _played = false;

  @override
  State<TideSplashGate> createState() => _TideSplashGateState();
}

class _TideSplashGateState extends State<TideSplashGate>
    with SingleTickerProviderStateMixin {
  // Short on purpose. The old brush intro ran 1150ms of writing plus a 900ms
  // hold to make sure it was noticed; the point now is the opposite, so this is
  // only long enough not to strobe — the ground is already on screen from the
  // platform launch theme, so all that actually changes is the word appearing
  // and the veil lifting.
  static const _fadeIn = Duration(milliseconds: 180);
  static const _hold = Duration(milliseconds: 380);
  static const _fadeOut = Duration(milliseconds: 320);

  late final AnimationController _c;
  late final Animation<double> _word;
  late final Animation<double> _veil;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _done = TideSplashGate._played;
    final total = _fadeIn + _hold + _fadeOut;
    _c = AnimationController(vsync: this, duration: total);
    final inEnd = _fadeIn.inMilliseconds / total.inMilliseconds;
    final outStart = (_fadeIn + _hold).inMilliseconds / total.inMilliseconds;
    _word = CurvedAnimation(
      parent: _c,
      curve: Interval(0, inEnd, curve: tideEase),
    );
    _veil = CurvedAnimation(
      parent: _c,
      curve: Interval(outStart, 1, curve: tideEase),
    );
    if (!_done) {
      TideSplashGate._played = true;
      _c.forward().whenComplete(() {
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
    // This layer has no Scaffold or Material above it, so its text used to
    // inherit Flutter's alarming fallback style and drew 모형 with a double
    // yellow underline. The floor now lives above the navigator in
    // `buildAppShell`, which covers this layer and the toast overlay together.
    //
    // The veil's own background stays fully opaque for as long as it is up:
    // fading the word in behind a translucent ground would show the half-built
    // app through it, which is the one thing a launch veil must not do.
    return ColoredBox(
      color: TideColors.ground,
      child: Stack(
        children: [
          const Positioned.fill(child: TideAurora()),
          Center(
            child: Opacity(
              opacity: _word.value,
              child: TideGlass(
                radius: TideRadius.panel,
                padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TideWordmark(size: 46),
                    const SizedBox(height: 10),
                    // The Korean the roundel used to carry, kept as a kicker so
                    // dropping the logo does not drop the identity with it.
                    Text(
                      '모형',
                      style: TideText.kicker(
                        size: 11,
                        color: TideColors.textAt(0.42),
                      ).copyWith(letterSpacing: 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
