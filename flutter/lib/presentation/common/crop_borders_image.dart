import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// [ImageProvider] decorator that trims solid-colour margins off the page art
/// before it reaches the widget tree — Mihon's "Crop borders" reader option
/// (Kotlin `ImageUtil.findBorders`).
///
/// It resolves the wrapped [inner] provider to a decoded frame, samples the
/// four corners for the page background colour, then scans inward from each
/// edge until a line that differs from the background appears. The content
/// rectangle is drawn into a fresh, smaller [ui.Image] which is handed back
/// through a [OneFrameImageStreamCompleter]. Because the result is an ordinary
/// decoded image, every downstream consumer (paged `BoxFit`, webtoon
/// aspect-ratio layout, double-tap zoom) keeps working with no special cases.
///
/// When no uniform border is found the original frame is returned untouched,
/// so full-bleed pages are never mis-cropped.
class CropBordersImageProvider
    extends ImageProvider<CropBordersImageProvider> {
  const CropBordersImageProvider(this.inner);

  /// The undecorated source image (file, archive entry, SAF doc, network…).
  final ImageProvider inner;

  @override
  Future<CropBordersImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CropBordersImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CropBordersImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _resolveAndCrop(key),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('cropped', key.inner),
      ],
    );
  }

  Future<ImageInfo> _resolveAndCrop(CropBordersImageProvider key) async {
    final original = await _resolveInner(key.inner);
    final rect = await _findContentRect(original);
    if (rect == null) {
      return ImageInfo(image: original);
    }
    final cropped = await _crop(original, rect);
    return ImageInfo(image: cropped);
  }

  /// Drive [provider]'s [ImageStream] to completion and hand back its
  /// decoded [ui.Image] (or its error).
  static Future<ui.Image> _resolveInner(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Returns the non-border content rectangle in image pixels, or `null` when
  /// nothing should be trimmed (no uniform margin, or a degenerate result).
  static Future<ui.Rect?> _findContentRect(ui.Image image) async {
    final w = image.width;
    final h = image.height;
    if (w < 8 || h < 8) return null;

    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final px = data.buffer.asUint8List();

    int idx(int x, int y) => (y * w + x) * 4;

    // Background colour from the average of the four corners. Solid manga
    // margins are uniform, so the corners agree; full-bleed art makes the
    // per-edge scans bail immediately, leaving the page untrimmed.
    final corners = <int>[idx(0, 0), idx(w - 1, 0), idx(0, h - 1), idx(w - 1, h - 1)];
    var bgR = 0, bgG = 0, bgB = 0;
    for (final c in corners) {
      bgR += px[c];
      bgG += px[c + 1];
      bgB += px[c + 2];
    }
    bgR ~/= 4;
    bgG ~/= 4;
    bgB ~/= 4;

    // Per-channel tolerance and the fraction of a sampled line that must match
    // the background for the line to count as part of the border.
    const threshold = 16;
    const lineMatchRatio = 0.985;
    final xStride = (w / 256).ceil().clamp(1, w);
    final yStride = (h / 256).ceil().clamp(1, h);

    bool isBg(int i) =>
        (px[i] - bgR).abs() <= threshold &&
        (px[i + 1] - bgG).abs() <= threshold &&
        (px[i + 2] - bgB).abs() <= threshold;

    bool rowIsBorder(int y) {
      var total = 0, bg = 0;
      for (var x = 0; x < w; x += xStride) {
        total++;
        if (isBg(idx(x, y))) bg++;
      }
      return bg >= total * lineMatchRatio;
    }

    bool colIsBorder(int x) {
      var total = 0, bg = 0;
      for (var y = 0; y < h; y += yStride) {
        total++;
        if (isBg(idx(x, y))) bg++;
      }
      return bg >= total * lineMatchRatio;
    }

    var top = 0;
    while (top < h - 1 && rowIsBorder(top)) {
      top++;
    }
    var bottom = h - 1;
    while (bottom > top && rowIsBorder(bottom)) {
      bottom--;
    }
    var left = 0;
    while (left < w - 1 && colIsBorder(left)) {
      left++;
    }
    var right = w - 1;
    while (right > left && colIsBorder(right)) {
      right--;
    }

    // Nothing trimmed → leave the image alone (avoids a pointless copy).
    if (top == 0 && left == 0 && bottom == h - 1 && right == w - 1) {
      return null;
    }
    // Degenerate / near-empty result (e.g. a fully uniform page) → leave alone.
    if (right - left < w ~/ 8 || bottom - top < h ~/ 8) {
      return null;
    }
    return ui.Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      (right + 1).toDouble(),
      (bottom + 1).toDouble(),
    );
  }

  /// Paints [rect] of [src] into a new image sized to the content rectangle.
  static Future<ui.Image> _crop(ui.Image src, ui.Rect rect) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dst = ui.Rect.fromLTWH(0, 0, rect.width, rect.height);
    canvas.drawImageRect(
      src,
      rect,
      dst,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    return picture.toImage(rect.width.round(), rect.height.round());
  }

  @override
  bool operator ==(Object other) =>
      other is CropBordersImageProvider && other.inner == inner;

  @override
  int get hashCode => inner.hashCode;
}
