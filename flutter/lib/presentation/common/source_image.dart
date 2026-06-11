import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/source/local_archive.dart';
import '../../data/source/saf.dart';
import 'crop_borders_image.dart';

/// Image widget that paints whatever a source hands us — local file path,
/// `file://` URI, a SAF `content://` document URI (Local source on Android),
/// or a remote HTTP(S) URL. Wraps [CachedNetworkImage] for network URLs,
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
  });

  final String url;
  final BoxFit fit;

  /// Decode-target width in PHYSICAL pixels. Covers and thumbnails should
  /// set this (≈ rendered logical width × devicePixelRatio) so a 1000px
  /// cover isn't decoded and cached at full resolution for a 130dp grid
  /// cell — full-res decodes across a scrolling grid thrash the image
  /// cache and are a major jank source. Leave null for reader pages, which
  /// legitimately need full resolution for zoom.
  final int? cacheWidth;
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

  /// The undecorated backend [ImageProvider] for [url] (same detection rules
  /// as the widget), exposed so non-widget callers — e.g. the reader's
  /// "Set as cover" action — can resolve a page's bytes through the same
  /// network/file/archive/SAF pipeline the viewer uses.
  static ImageProvider providerFor(String url, {Map<String, String>? headers}) {
    return SourceImage(url: url, headers: headers)._backendProvider();
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
    return CachedNetworkImageProvider(url, headers: headers);
  }

  @override
  Widget build(BuildContext context) {
    final img = _buildImage(context);
    if (!rotateToFit) return img;
    // Probe the undecorated source bytes for orientation and rotate only the
    // wide (double-spread) pages, leaving normal portrait pages untouched.
    return _RotateToFitIfWide(
      provider: _backendProvider(),
      invert: rotateInvert,
      child: img,
    );
  }

  Widget _buildImage(BuildContext context) {
    if (cropBorders) {
      return Image(
        image: CropBordersImageProvider(_backendProvider()),
        fit: fit,
        frameBuilder: placeholder == null
            ? null
            : (ctx, child, frame, wasSync) {
                if (frame != null || wasSync) return child;
                return placeholder!(ctx);
              },
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    if (_isArchive) {
      return Image(
        image: cacheWidth == null
            ? _ArchiveImageProvider(url)
            : ResizeImage(_ArchiveImageProvider(url), width: cacheWidth),
        fit: fit,
        frameBuilder: placeholder == null
            ? null
            : (ctx, child, frame, wasSync) {
                if (frame != null || wasSync) return child;
                return placeholder!(ctx);
              },
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    if (_isContent) {
      return Image(
        image: cacheWidth == null
            ? _SafImageProvider(url)
            : ResizeImage(_SafImageProvider(url), width: cacheWidth),
        fit: fit,
        frameBuilder: placeholder == null
            ? null
            : (ctx, child, frame, wasSync) {
                if (frame != null || wasSync) return child;
                return placeholder!(ctx);
              },
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    if (_isLocal) {
      return Image.file(
        File(_localPath),
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      httpHeaders: headers,
      memCacheWidth: cacheWidth,
      placeholder: placeholder == null
          ? null
          : (ctx, _) => placeholder!(ctx),
      errorWidget: (ctx, _, error) =>
          errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
    );
  }
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

class _DefaultErrorBox extends StatelessWidget {
  const _DefaultErrorBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 36),
    );
  }
}
