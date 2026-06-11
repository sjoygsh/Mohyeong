import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
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

  /// Content-rect memo, keyed by the inner provider (value equality for
  /// file/network backends). Without it, an ImageCache eviction re-ran the
  /// whole border scan on re-display. Null value = "scanned, nothing to
  /// trim". Small LRU — rects are tiny, the cap just bounds growth.
  static final LinkedHashMap<ImageProvider, ui.Rect?> _rectCache =
      LinkedHashMap<ImageProvider, ui.Rect?>();
  static const int _rectCacheCap = 256;

  Future<ImageInfo> _resolveAndCrop(CropBordersImageProvider key) async {
    final original = await _resolveInner(key.inner);
    final ui.Rect? rect;
    if (_rectCache.containsKey(key.inner)) {
      rect = _rectCache.remove(key.inner);
      _rectCache[key.inner] = rect; // refresh LRU position
    } else {
      rect = await _findContentRect(original);
      _rectCache[key.inner] = rect;
      while (_rectCache.length > _rectCacheCap) {
        _rectCache.remove(_rectCache.keys.first);
      }
    }
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

  /// Returns the non-border content rectangle in FULL-RES image pixels, or
  /// `null` when nothing should be trimmed (no uniform margin, or a
  /// degenerate result).
  ///
  /// The scan runs on a ≤256px downsample: border detection doesn't need
  /// full resolution, and the full-res `toByteData` readback (~8 MB for a
  /// typical page) plus the pixel loops used to land on the UI isolate at
  /// exactly the moment the user swiped to the page.
  static Future<ui.Rect?> _findContentRect(ui.Image image) async {
    final fullW = image.width;
    final fullH = image.height;
    if (fullW < 8 || fullH < 8) return null;

    const maxDim = 256;
    final downscale =
        (maxDim / math.max(fullW, fullH)).clamp(0.0, 1.0).toDouble();
    ui.Image sample = image;
    var owned = false;
    if (downscale < 1.0) {
      final sw = math.max(8, (fullW * downscale).round());
      final sh = math.max(8, (fullH * downscale).round());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, fullW.toDouble(), fullH.toDouble()),
        ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      sample = await picture.toImage(sw, sh);
      picture.dispose();
      owned = true;
    }

    final w = sample.width;
    final h = sample.height;
    final data = await sample.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (owned) sample.dispose();
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
    // Scale the sample-space rect back to full-res pixels, biased outward
    // (floor/ceil) so the crop never eats into content at the edges.
    final invX = fullW / w;
    final invY = fullH / h;
    return ui.Rect.fromLTRB(
      (left * invX).floorToDouble().clamp(0, fullW.toDouble()),
      (top * invY).floorToDouble().clamp(0, fullH.toDouble()),
      ((right + 1) * invX).ceilToDouble().clamp(0, fullW.toDouble()),
      ((bottom + 1) * invY).ceilToDouble().clamp(0, fullH.toDouble()),
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
