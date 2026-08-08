import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/material.dart';

import '../../data/network/webview_http_client.dart';
import '../../data/storage/app_cache.dart';
import '../../data/source/local_archive.dart';
import '../../data/network/page_downloader.dart';
import '../../data/source/page_fetch_queue.dart';
import '../../data/source/saf.dart';
import 'crop_borders_image.dart';

/// Image widget that paints whatever a source hands us — local file path,
/// `file://` URI, a SAF `content://` document URI (Local source on Android),
/// or a remote HTTP(S) URL. Wraps [_NetworkImageWithWebViewFallback] for
/// network URLs,
/// [Image.file] for local paths, and a [_SafImageProvider] for content URIs,
/// so the same call sites in Library / History / Manga details / Reader /
/// Browse handle every backend uniformly.
///
/// Detection rules:
///   * starts with `content://` → read bytes through the native SAF channel
///   * starts with `file://` → strip the scheme, render as a file path
///   * an absolute filesystem path (`C:\…` on Windows, `/…` elsewhere) →
///     render as a file path
///   * anything else → treated as a network URL
class SourceImage extends StatelessWidget {
  const SourceImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.headers,
    this.placeholder,
    this.errorWidget,
    this.cropBorders = false,
    this.rotateToFit = false,
    this.rotateInvert = false,
    this.cacheWidth,
    this.fadeIn = true,
    this.opacity,
    this.fullResolution = false,
  });

  final String url;
  final BoxFit fit;

  /// Paint-time opacity forwarded to the underlying [Image] — applied while
  /// rasterising the bitmap, so unlike an [Opacity] wrapper it costs no
  /// compositing layer. Browse/global-search dim in-library covers with this
  /// (Mihon's 0.34 alpha), which used to saveLayer every dimmed cell each
  /// scrolled frame.
  final Animation<double>? opacity;

  /// Fade the image in over 300ms when it loads asynchronously. Mirrors
  /// Mihon's global Coil `crossfade(300)` (App.kt) — on by default for
  /// covers/thumbnails everywhere; the reader page lists pass false, matching
  /// `ReaderPageImageView`'s explicit `crossfade(false)`. Synchronous loads
  /// (memory-cache hits) never fade, same as Coil.
  final bool fadeIn;

  /// Decode-target width in PHYSICAL pixels. Covers and thumbnails should
  /// set this (≈ rendered logical width × devicePixelRatio) so a 1000px
  /// cover isn't decoded and cached at full resolution for a 130dp grid
  /// cell — full-res decodes across a scrolling grid thrash the image
  /// cache and are a major jank source. Leave null for reader pages, which
  /// legitimately need full resolution for zoom.
  final int? cacheWidth;

  /// When the network fetch falls back to the offscreen WebView (fingerprint-
  /// walled CDNs), pull the image's ORIGINAL bytes instead of the 480px
  /// cover-sized re-encode. Reader page lists set this — a cover-sized page
  /// upscaled to a full screen is visibly pixelated. Orthogonal to
  /// [cacheWidth], which caps the DECODE of whatever bytes arrive.
  final bool fullResolution;
  final Map<String, String>? headers;
  final WidgetBuilder? placeholder;
  final Widget Function(BuildContext, Object error)? errorWidget;

  /// Trim solid-colour page margins before display (reader "Crop borders").
  /// Off everywhere except the reader page list. When on, the backend
  /// [ImageProvider] is wrapped in a [CropBordersImageProvider].
  final bool cropBorders;

  /// Reader "rotate double pages to fit": when the decoded image is wider
  /// than it is tall (a landscape double-spread), rotate it 90° so it fills
  /// a portrait screen. Mirrors Mihon's `dualPageRotateToFit`. Off everywhere
  /// except the paged reader page list.
  final bool rotateToFit;

  /// Rotate anticlockwise (−90°) instead of clockwise when [rotateToFit] is
  /// on. Mihon's `dualPageRotateToFitInvert`.
  final bool rotateInvert;

  /// The [ImageProvider] for [url] (same detection rules as the widget),
  /// exposed so non-widget callers — the reader's precache / aspect probe /
  /// split-half / "Set as cover" pipelines — can resolve a page's bytes
  /// through the same pipeline the viewer uses. Pass the SAME [cacheWidth]
  /// and [fullResolution] the displaying widget uses: they are part of the
  /// [ImageCache] key, and a mismatch decodes the page twice.
  static ImageProvider providerFor(
    String url, {
    Map<String, String>? headers,
    int? cacheWidth,
    bool fullResolution = false,
  }) {
    return SourceImage(
      url: url,
      headers: headers,
      cacheWidth: cacheWidth,
      fullResolution: fullResolution,
    )._displayProvider();
  }

  bool get _isArchive => isArchivePageUrl(url);

  bool get _isContent => url.startsWith('content://');

  bool get _isLocal {
    if (url.startsWith('file://')) return true;
    if (url.isEmpty) return false;
    // Windows absolute path (drive letter) — `C:\foo\bar.jpg`.
    if (url.length >= 3 && url[1] == ':' && (url[2] == '\\' || url[2] == '/')) {
      return true;
    }
    // POSIX absolute path.
    if (url.startsWith('/')) return true;
    return false;
  }

  String get _localPath {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    return url;
  }

  /// The undecorated backend [ImageProvider] for this URL, used when borders
  /// are cropped (the crop decorator wraps it and the standard [Image] widget
  /// renders the trimmed result).
  ImageProvider _backendProvider() {
    if (_isArchive) return _ArchiveImageProvider(url);
    if (_isContent) return _SafImageProvider(url);
    if (_isLocal) return FileImage(File(_localPath));
    return _NetworkImageWithWebViewFallback(url, headers, fullResolution);
  }

  /// [_backendProvider] with the [cacheWidth] decode cap applied — the ONE
  /// provider (and [ImageCache] key) every consumer of this url+config must
  /// share: the display branches, the crop/rotate decorators' probes, and
  /// [providerFor] (reader precache/aspect/split/set-as-cover). Any site
  /// resolving the backend without the cap would decode the page a second
  /// time at full size.
  ImageProvider _displayProvider() {
    final backend = _backendProvider();
    final cw = cacheWidth;
    return cw == null ? backend : _ValueResizeImage(backend, width: cw);
  }

  @override
  Widget build(BuildContext context) {
    final img = _buildImage(context);
    if (!rotateToFit) return img;
    // Probe the displayed decode for orientation and rotate only the wide
    // (double-spread) pages, leaving normal portrait pages untouched.
    return _RotateToFitIfWide(
      provider: _displayProvider(),
      invert: rotateInvert,
      child: img,
    );
  }

  /// frameBuilder shared by every backend branch: [placeholder] until the
  /// first frame, faded in per [fadeIn]. Null when there's nothing to wrap.
  ImageFrameBuilder? _frameBuilder() {
    final ph = placeholder;
    if (!fadeIn && ph == null) return null;
    return (ctx, child, frame, wasSync) {
      if (wasSync) return child;
      if (!fadeIn) {
        return frame == null ? ph!(ctx) : child;
      }
      return _CrossfadeFrame(
        frame: frame,
        placeholder: ph?.call(ctx),
        child: child,
      );
    };
  }

  Widget _buildImage(BuildContext context) {
    if (cropBorders) {
      return Image(
        image: CropBordersImageProvider(_displayProvider()),
        fit: fit,
        opacity: opacity,
        frameBuilder: _frameBuilder(),
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    if (_isArchive || _isContent || _isLocal) {
      return Image(
        image: _displayProvider(),
        fit: fit,
        opacity: opacity,
        frameBuilder: _frameBuilder(),
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    // Same provider (and therefore the same ImageCache key) as
    // [providerFor], so the reader's precache / aspect-probe /
    // crop-and-rotate pipelines and this widget all share ONE decode per URL.
    // The WebView fingerprint-wall fallback lives inside the provider.
    return Image(
      image: _displayProvider(),
      fit: fit,
      opacity: opacity,
      gaplessPlayback: true,
      frameBuilder: _frameBuilder(),
      errorBuilder: (ctx, error, _) =>
          errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
    );
  }
}

/// [ResizeImage] with value equality. [ResizeImage] itself compares by
/// identity, which is fine for the [ImageCache] (its obtainKey emits a
/// value-equal key) but breaks the decorator providers that key on their
/// INNER provider's equality — [CropBordersImageProvider] and
/// [HalfPageImageProvider] would see a brand-new inner every rebuild, re-
/// running the crop and missing the content-rect memo each time.
class _ValueResizeImage extends ResizeImage {
  const _ValueResizeImage(super.imageProvider, {super.width});

  @override
  bool operator ==(Object other) =>
      other is _ValueResizeImage &&
      other.imageProvider == imageProvider &&
      other.width == width;

  @override
  int get hashCode => Object.hash(imageProvider, width);
}

/// [ImageProvider] that loads its bytes from a SAF `content://` document URI
/// through the native [Saf] channel, then decodes them with the engine's
/// standard codec path. Caching is handled by Flutter's [ImageCache] keyed on
/// the URI, so re-displaying a page doesn't re-read it from disk.
class _SafImageProvider extends ImageProvider<_SafImageProvider> {
  const _SafImageProvider(this.uri);

  final String uri;

  @override
  Future<_SafImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SafImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _SafImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.uri,
    );
  }

  Future<ui.Codec> _loadAsync(
    _SafImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await Saf.readBytes(key.uri);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('SAF read returned no bytes for ${key.uri}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _SafImageProvider && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// [ImageProvider] that loads a single image entry out of a CBZ/ZIP archive
/// chapter via [readArchiveEntry] (which reads + caches the archive through
/// the SAF channel or `dart:io`). Keyed on the full `archive://` URL so
/// Flutter's [ImageCache] de-dupes re-displays of the same page.
class _ArchiveImageProvider extends ImageProvider<_ArchiveImageProvider> {
  const _ArchiveImageProvider(this.url);

  final String url;

  @override
  Future<_ArchiveImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ArchiveImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _ArchiveImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    _ArchiveImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final decoded = decodeArchivePageUrl(key.url);
    final bytes = await readArchiveEntry(decoded.locator, decoded.entry);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Archive read returned no bytes for ${key.url}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _ArchiveImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// The ONE network [ImageProvider] behind both the [SourceImage] widget and
/// every provider-based consumer ([SourceImage.providerFor], the crop /
/// rotate / dual-page reader pipelines, precache, aspect probes) — a single
/// [ImageCache] key per URL, so a page decoded by any of them is reused by
/// all. Bytes come from the shared image disk cache; on a fetch failure —
/// commonly a 403 from a CDN that fingerprint-blocks non-browser TLS — the
/// offscreen WebView ([WebViewHttpClient.fetchImageBytes]) is tried before
/// giving up.
class _NetworkImageWithWebViewFallback
    extends ImageProvider<_NetworkImageWithWebViewFallback> {
  const _NetworkImageWithWebViewFallback(
    this.url,
    this.headers, [
    this.fullResolution = false,
  ]);

  final String url;
  final Map<String, String>? headers;

  /// Ask the WebView fallback for the image's original bytes instead of the
  /// 480px cover-sized re-encode (reader pages). Part of the cache key.
  final bool fullResolution;

  /// URLs whose ORIGIN image is genuinely cover-sized (≤480px both axes),
  /// confirmed by a fresh fetch — so the poisoned-cache probe in [_loadAsync]
  /// doesn't re-fetch them on every load. Session-lived, bounded.
  static final Set<String> _confirmedSmall = <String>{};

  /// Byte ceiling under which a cached entry could plausibly BE the old 480px
  /// WebView re-encode. Anything fatter is a real page, so the poisoned-cache
  /// probe below can skip it — see [_loadAsync].
  static const int _maxCoverSizedBytes = 512 * 1024;

  @override
  Future<_NetworkImageWithWebViewFallback> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture<_NetworkImageWithWebViewFallback>(this);

  @override
  ImageStreamCompleter loadImage(
    _NetworkImageWithWebViewFallback key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    _NetworkImageWithWebViewFallback key,
    ImageDecoderCallback decode,
  ) async {
    // Exactly one of these ends up set. `path` is the fast lane: the engine
    // reads the file itself ([ui.ImmutableBuffer.fromFilePath]) instead of
    // this isolate copying a multi-megabyte page onto the Dart heap first,
    // which on a fast webtoon scroll is several copies per second.
    Uint8List? bytes;
    String? path;
    var fromDiskCache = false;
    try {
      // Reader pages return from inside this branch, which also skips the
      // poisoned-cache probe further down: that probe exists for entries the
      // old WebView path wrote at 480px, and neither the page store nor a
      // legacy entry big enough to be a real page can be one.
      if (key.fullResolution) {
        // Reader pages fetch on a background isolate; see [PageDownloader] for
        // the measurement that put them there. Covers fall through to the
        // shared cache manager unchanged.
        final stored = await PageDownloader.cachedPath(key.url);
        if (stored != null) {
          path = stored;
          fromDiskCache = true;
        } else {
          // Pages cached before this store existed still live in the cache
          // manager. Use that file in place rather than re-downloading — a
          // path lookup and a stat, no bytes onto the Dart heap.
          final legacy =
              (await appImageCacheManager.getFileFromCache(key.url))?.file;
          if (legacy != null) {
            path = legacy.path;
            fromDiskCache = true;
          } else {
            path = await PageFetchQueue.run(
              key.url,
              () => PageDownloader.fetch(key.url, key.headers),
            );
          }
        }
        final buffer = await ui.ImmutableBuffer.fromFilePath(path!);
        return decode(buffer);
      }
      // Read-through to the legacy default store first on a miss: upgraded
      // installs have their whole cover library cached there, and without
      // this an offline relaunch after the upgrade rendered every cover as
      // an error box. Hits migrate into the new store lazily.
      var file = (await appImageCacheManager.getFileFromCache(key.url))?.file;
      if (file == null) {
        final legacy = await DefaultCacheManager().getFileFromCache(key.url);
        if (legacy != null) {
          bytes = await legacy.file.readAsBytes();
          unawaited(appImageCacheManager.putFile(key.url, bytes));
          fromDiskCache = true;
        } else {
          // Reader pages queue behind the read position here; covers and
          // everything else pass straight through. See [PageFetchQueue].
          // Kept in its own local: the cache manager hands back the `file`
          // package's File, not `dart:io`'s, so it can't go through [file].
          final downloaded = await PageFetchQueue.run(
            key.url,
            () => appImageCacheManager.getSingleFile(
              key.url,
              headers: key.headers ?? const {},
            ),
          );
          path = downloaded.path;
        }
      } else {
        path = file.path;
        fromDiskCache = true;
      }
    } catch (_) {
      // The WebView round trip is serialized host-side and slower still than a
      // plain download, so it belongs in the queue for the same reason.
      final fallback = await PageFetchQueue.run(
        key.url,
        () => WebViewHttpClient.instance
            .fetchImageBytes(key.url, fullResolution: key.fullResolution),
      );
      if (fallback == null || fallback.isEmpty) rethrow;
      bytes = fallback;
      path = null;
      // Persist so the next cold load is a disk hit instead of a doomed
      // HTTP attempt plus a serialized WebView round trip.
      unawaited(appImageCacheManager.putFile(key.url, fallback));
    }
    if (key.fullResolution &&
        fromDiskCache &&
        !_confirmedSmall.contains(key.url)) {
      // Poisoned cache entry: before full-resolution fetches existed, the
      // WebView fallback persisted 480px cover-sized bytes under the page's
      // URL — a full-screen page rendered from them is visibly pixelated.
      // Replace with origin bytes; if the origin image is GENUINELY that
      // small, remember it so this doesn't re-fetch on every load. On
      // refetch failure keep serving the small bytes (better than an error
      // box) and stay unmarked so a later load retries.
      //
      // Gated on the entry's SIZE first. This probe used to run on every
      // full-resolution disk hit, so every reader page was read into the
      // Dart heap and header-parsed once purely to rule the poisoning out —
      // a cost paid per page, forever, for a one-off migration hazard. Only
      // bytes small enough to be that 480px re-encode can be poisoned.
      final length = bytes?.length ?? await File(path!).length();
      if (length <= _maxCoverSizedBytes) {
        bytes ??= await File(path!).readAsBytes();
        if (await _isCoverSized(bytes)) {
          final fresh = await _refetchOriginal(key);
          if (fresh != null && fresh.isNotEmpty) {
            bytes = fresh;
            path = null;
            if (await _isCoverSized(fresh)) {
              if (_confirmedSmall.length >= 512) {
                _confirmedSmall.remove(_confirmedSmall.first);
              }
              _confirmedSmall.add(key.url);
            }
          }
        }
      }
    }
    final buffer = bytes != null
        ? await ui.ImmutableBuffer.fromUint8List(bytes)
        : await ui.ImmutableBuffer.fromFilePath(path!);
    return decode(buffer);
  }

  /// Whether [bytes] decode to at most the old WebView fallback's 480px
  /// cover cap on both axes. Header-only parse — no full decode.
  static Future<bool> _isCoverSized(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final small = descriptor.width <= 480 && descriptor.height <= 480;
      descriptor.dispose();
      return small;
    } catch (_) {
      return false;
    } finally {
      buffer?.dispose();
    }
  }

  /// Force-fetch the origin bytes past the (poisoned) disk cache: fresh HTTP
  /// download first (it also replaces the cache entry), the full-resolution
  /// WebView path when the CDN blocks plain HTTP. Null when both fail.
  Future<Uint8List?> _refetchOriginal(
    _NetworkImageWithWebViewFallback key,
  ) async {
    try {
      final downloaded = await appImageCacheManager.downloadFile(
        key.url,
        authHeaders: key.headers,
      );
      return await downloaded.file.readAsBytes();
    } catch (_) {
      final viaWebView = await WebViewHttpClient.instance
          .fetchImageBytes(key.url, fullResolution: true);
      if (viaWebView != null && viaWebView.isNotEmpty) {
        unawaited(appImageCacheManager.putFile(key.url, viaWebView));
      }
      return viaWebView;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _NetworkImageWithWebViewFallback &&
      other.url == url &&
      other.fullResolution == fullResolution &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(url, fullResolution);
}

/// Rotates [child] a quarter turn when [provider]'s image is wider than it
/// is tall, so a landscape double-spread fills a portrait screen (reader
/// "rotate double pages to fit"). Portrait/square pages pass through
/// unrotated. The orientation is resolved by listening to the provider's
/// stream once; until it resolves the child renders unrotated (a single
/// frame), then the wide pages flip into place. [RotatedBox] swaps the
/// child's layout constraints, so the inner [BoxFit] still fills correctly.
class _RotateToFitIfWide extends StatefulWidget {
  const _RotateToFitIfWide({
    required this.provider,
    required this.invert,
    required this.child,
  });

  final ImageProvider provider;
  final bool invert;
  final Widget child;

  @override
  State<_RotateToFitIfWide> createState() => _RotateToFitIfWideState();
}

class _RotateToFitIfWideState extends State<_RotateToFitIfWide> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool? _wide;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _RotateToFitIfWide old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) {
      _wide = null;
      _resolve();
    }
  }

  void _resolve() {
    _detach();
    final stream = widget.provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        final wide = info.image.width > info.image.height;
        info.image.dispose();
        if (mounted && wide != _wide) setState(() => _wide = wide);
      },
      onError: (_, _) {
        // Leave unrotated on decode failure; the child shows its own error.
        if (mounted && _wide != false) setState(() => _wide = false);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_wide != true) return widget.child;
    return RotatedBox(
      quarterTurns: widget.invert ? 3 : 1,
      child: widget.child,
    );
  }
}

/// One decoded-frame slot with the Coil-style crossfade: transparent until
/// the first frame arrives, then a 300ms linear fade drawn over the
/// placeholder, which is dropped once the fade lands. [frame] falling back to
/// null later (gaplessPlayback resets it when the provider changes, e.g. a
/// cover refresh) does NOT re-hide the image — the old frame keeps painting,
/// so refreshes stay gapless instead of blinking.
class _CrossfadeFrame extends StatefulWidget {
  const _CrossfadeFrame({
    required this.frame,
    required this.placeholder,
    required this.child,
  });

  final int? frame;
  final Widget? placeholder;
  final Widget child;

  @override
  State<_CrossfadeFrame> createState() => _CrossfadeFrameState();
}

class _CrossfadeFrameState extends State<_CrossfadeFrame> {
  bool _hadFrame = false;
  bool _settled = false;

  @override
  Widget build(BuildContext context) {
    _hadFrame = _hadFrame || widget.frame != null;
    final image = AnimatedOpacity(
      // Coil's CrossfadeDrawable: linear alpha over 300ms (App.kt crossfade).
      opacity: _hadFrame ? 1 : 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.linear,
      onEnd: () {
        if (_hadFrame && !_settled && mounted) {
          setState(() => _settled = true);
        }
      },
      child: widget.child,
    );
    final ph = widget.placeholder;
    if (ph == null || _settled) return image;
    return Stack(fit: StackFit.passthrough, children: [ph, image]);
  }
}

/// What a cover that would not load leaves behind.
///
/// This is the most-seen failure state in the app — every grid, every browse
/// result, every reader page that 403s — and it was a flat slab out of the
/// Material scheme with an untinted glyph on it. Held to the same ground and
/// the same quiet ink as the rest of Tide, a missing cover reads as an empty
/// slot rather than as a piece of a different app.
class _DefaultErrorBox extends StatelessWidget {
  const _DefaultErrorBox();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF161A28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 30,
          color: Colors.white.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}
