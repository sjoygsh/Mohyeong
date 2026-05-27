import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Image widget that paints whatever a source hands us — local file path,
/// `file://` URI, or remote HTTP(S) URL. Wraps [CachedNetworkImage] for
/// network URLs and [Image.file] for local paths so the same call sites
/// in Library / History / Manga details / Reader / Browse handle both
/// online sources and the Local source uniformly.
///
/// Detection rules:
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
  });

  final String url;
  final BoxFit fit;
  final Map<String, String>? headers;
  final WidgetBuilder? placeholder;
  final Widget Function(BuildContext, Object error)? errorWidget;

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

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      return Image.file(
        File(_localPath),
        fit: fit,
        errorBuilder: (ctx, error, _) =>
            errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      httpHeaders: headers,
      placeholder: placeholder == null
          ? null
          : (ctx, _) => placeholder!(ctx),
      errorWidget: (ctx, _, error) =>
          errorWidget?.call(ctx, error) ?? const _DefaultErrorBox(),
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
