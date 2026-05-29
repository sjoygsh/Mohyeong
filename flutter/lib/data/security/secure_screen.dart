import 'package:flutter/services.dart';

/// Thin wrapper over the native `app.mohyeong/secure_flag` method channel,
/// which sets or clears Android's `WindowManager.LayoutParams.FLAG_SECURE`
/// on the host activity. FLAG_SECURE blocks screenshots and hides window
/// contents from the recent-apps thumbnail.
///
/// No-ops on platforms without a handler (e.g. iOS / desktop) — the channel
/// call throws `MissingPluginException`, which we swallow.
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('app.mohyeong/secure_flag');

  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } on MissingPluginException {
      // Platform has no FLAG_SECURE concept; ignore.
    }
  }
}
