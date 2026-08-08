import 'dart:async';

import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

/// Per-frame build and raster timings, printed to logcat.
///
/// Off unless the build passes `--dart-define=FRAME_STATS=true`, so nothing
/// here runs in a shipped build.
///
/// This exists because the obvious device instruments do not work on this
/// project. `dumpsys gfxinfo` reports zero frames (Flutter draws to its own
/// SurfaceView, not through HWUI), and `dumpsys SurfaceFlinger --latency`
/// returned all-zero rows for every app layer on the test phone while the
/// screen was visibly animating — after first returning two plausible-looking
/// but wrong numbers. Flutter's own [SchedulerBinding.addTimingsCallback] is
/// the ground truth, it works in release, and it separates the two costs that
/// need telling apart: BUILD time is the UI thread (our widget code), RASTER
/// time is the GPU thread (blurs, saveLayers, clips, texture uploads). Which
/// one dominates decides where the fix goes.
abstract final class FrameStats {
  static const bool enabled = bool.fromEnvironment('FRAME_STATS');

  static final List<FrameTiming> _window = <FrameTiming>[];
  static const String _label = 'scroll';

  /// Reports every [_every] and clears, so a scripted scroll shows up as one
  /// or two lines in logcat with nothing to trigger from the host.
  static const Duration _every = Duration(seconds: 2);

  static void install() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(_every, (_) => report());
  }

  static void _onTimings(List<FrameTiming> timings) {
    _window.addAll(timings);
    // Cap so a long session can't grow this without bound.
    if (_window.length > 4000) {
      _window.removeRange(0, _window.length - 4000);
    }
  }

  static void report() {
    if (!enabled || _window.isEmpty) return;
    final build = <double>[];
    final raster = <double>[];
    final total = <double>[];
    // buildStart - vsyncStart: how long the UI thread took to even BEGIN the
    // frame. Big here with small build/raster means the thread was busy with
    // something that is not widget work — platform-channel replies, image
    // decode completions, GC — and no amount of optimising build or raster
    // will move it.
    final wait = <double>[];
    for (final t in _window) {
      build.add(t.buildDuration.inMicroseconds / 1000);
      raster.add(t.rasterDuration.inMicroseconds / 1000);
      total.add(t.totalSpan.inMicroseconds / 1000);
      wait.add(t.vsyncOverhead.inMicroseconds / 1000);
    }
    build.sort();
    raster.sort();
    total.sort();
    wait.sort();
    String p(List<double> v, double q) =>
        v[(v.length * q).clamp(0, v.length - 1).toInt()].toStringAsFixed(1);
    final janky = total.where((t) => t > 16.7).length;
    // CADENCE — the judder metric, and the one this file was missing.
    //
    // build/raster/janky all answer "was each frame cheap", and on this reader
    // the answer has always been yes. None of them answer "did the frames
    // arrive EVENLY", which is what the eye actually reads as smooth. A frame
    // can cost 4ms and still be presented a whole vsync late because the UI
    // thread was busy with something that is not widget work; the run then
    // alternates 16.7 / 33.4 and looks exactly like frame-pacing stutter in a
    // game, while janky% sits at 0. So: the gaps between consecutive frames'
    // vsyncs, and a count of the ones that skipped a display refresh.
    final gaps = <double>[];
    for (var i = 1; i < _window.length; i++) {
      final prev =
          _window[i - 1].timestampInMicroseconds(FramePhase.vsyncStart);
      final now = _window[i].timestampInMicroseconds(FramePhase.vsyncStart);
      final d = (now - prev) / 1000;
      // Ignore the idle gaps between separate bursts of activity — a pause
      // with nothing on screen moving is not a dropped frame.
      if (d > 0 && d < 200) gaps.add(d);
    }
    gaps.sort();
    final skipped = gaps.where((g) => g > 25).length;
    final elapsed = gaps.fold<double>(0, (a, b) => a + b);
    final fps = elapsed > 0 ? 1000 * gaps.length / elapsed : 0.0;
    // `print`, not `developer.log`: the latter goes to the VM service, which
    // nothing is attached to in a release build, so it never reaches logcat.
    // ignore: avoid_print
    print(
      'FRAMESTATS[$_label] n=${_window.length} '
      'janky=${(100 * janky / _window.length).toStringAsFixed(0)}% | '
      'build p50=${p(build, .5)} p90=${p(build, .9)} p99=${p(build, .99)} '
      'max=${build.last.toStringAsFixed(1)} | '
      'raster p50=${p(raster, .5)} p90=${p(raster, .9)} p99=${p(raster, .99)} '
      'max=${raster.last.toStringAsFixed(1)} | '
      'vsync-wait p50=${p(wait, .5)} p90=${p(wait, .9)} '
      'max=${wait.last.toStringAsFixed(1)}',
    );
    if (gaps.isNotEmpty) {
      // ignore: avoid_print
      print(
        'FRAMECADENCE[$_label] frames=${gaps.length + 1} '
        'fps=${fps.toStringAsFixed(1)} '
        'skipped=$skipped (${(100 * skipped / gaps.length).toStringAsFixed(1)}%) '
        '| gap p50=${p(gaps, .5)} p90=${p(gaps, .9)} p99=${p(gaps, .99)} '
        'max=${gaps.last.toStringAsFixed(1)}',
      );
    }
    _window.clear();
  }
}
