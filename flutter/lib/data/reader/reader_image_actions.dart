import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Thin wrapper over the native `app.mohyeong/image_actions` method channel —
/// the backends for the reader's long-press page-actions sheet (Mihon
/// `ReaderPageActionsDialog`): share the page image, copy the image itself
/// to the clipboard, and save it into `Pictures/<app label>`.
///
/// Each action stages the page bytes into `cacheDir/shared_image/` first
/// (wiping the previous stage, like Mihon's `cacheImageDir` which keeps only
/// the last shared image) and hands the native side a plain file path; the
/// manifest `FileProvider` turns it into a shareable `content://` URI.
class ReaderImageActions {
  ReaderImageActions._();

  static const _channel = MethodChannel('app.mohyeong/image_actions');

  /// Mihon `DiskUtil.buildValidFilename`: replace characters that are
  /// invalid in filenames; the byte-length cap is irrelevant at our sizes.
  static String buildValidFilename(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  static Future<String> _stage(Uint8List bytes, String filename) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}shared_image',
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Android share sheet with the image attached and [message] as the share
  /// text (Mihon's `share_page_info`: "title: chapter, page N").
  static Future<void> share(
    Uint8List bytes, {
    required String filename,
    required String message,
  }) async {
    final path = await _stage(bytes, filename);
    await _channel.invokeMethod<void>('share', {
      'path': path,
      'message': message,
    });
  }

  /// Plain-text share sheet (Kotlin `String.toShareIntent(type =
  /// "text/plain")`) — used for chapter / page URLs.
  static Future<void> shareText(String text) async {
    await _channel.invokeMethod<void>('shareText', {'text': text});
  }

  /// Put the image itself on the clipboard (`ClipData.newUri`, matching
  /// `ReaderActivity.onCopyImageResult`). Android 13+ shows its own clip
  /// preview, so no toast is needed.
  static Future<void> copyToClipboard(
    Uint8List bytes, {
    required String filename,
  }) async {
    final path = await _stage(bytes, filename);
    await _channel.invokeMethod<void>('copyToClipboard', {'path': path});
  }

  /// Save into `Pictures/<app label>/` via MediaStore (Mihon ImageSaver
  /// `Location.Pictures`).
  static Future<void> saveToPictures(
    Uint8List bytes, {
    required String displayName,
  }) async {
    final path = await _stage(bytes, '$displayName.png');
    await _channel.invokeMethod<void>('saveToPictures', {
      'path': path,
      'displayName': displayName,
      'mime': 'image/png',
    });
  }
}
