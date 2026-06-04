import 'package:flutter/services.dart';

/// Thin wrapper over the native `app.mohyeong/volume_keys` method channel.
///
/// When interception is enabled, the host activity consumes the hardware
/// volume up/down keys (suppressing the system volume UI) and forwards each
/// press to Dart via the `volumeKey` callback with `"up"` or `"down"`. The
/// reader enables interception only while a chapter is open and the chrome
/// is hidden, so volume keys behave normally everywhere else.
///
/// No-ops on platforms without a handler (e.g. iOS / desktop) — the channel
/// call throws `MissingPluginException`, which we swallow.
class ReaderVolumeKeys {
  ReaderVolumeKeys._();

  static const _channel = MethodChannel('app.mohyeong/volume_keys');

  /// Turn native volume-key interception on or off.
  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // Platform has no volume-key interception; ignore.
    }
  }

  /// Register (or clear, when [onKey] is null) the callback fired for each
  /// intercepted volume-key press. [up] is true for volume-up.
  static void setListener(void Function(bool up)? onKey) {
    if (onKey == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') {
        onKey(call.arguments == 'up');
      }
      return null;
    });
  }
}
