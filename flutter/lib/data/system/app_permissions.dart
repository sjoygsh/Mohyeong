/// Dart facade over the native permissions MethodChannel
/// (`app.mohyeong/permissions`, handled in MainActivity.kt).
///
/// Covers the two runtime grants the onboarding Permission step surfaces:
/// POST_NOTIFICATIONS (library-update / download notifications, Android 13+)
/// and battery-optimization exemption (so background library updates aren't
/// killed). Mirrors the relevant rows of Mihon's PermissionStep — minus the
/// install-unknown-apps row, which only applies to Mihon's APK extensions
/// (Mohyeong loads JS extensions) and the telemetry switches Mohyeong has no
/// equivalent for.
library;

import 'package:flutter/services.dart';

class AppPermissions {
  AppPermissions._();

  static const MethodChannel _channel =
      MethodChannel('app.mohyeong/permissions');

  static Future<bool> hasNotificationPermission() async =>
      await _channel.invokeMethod<bool>('hasNotificationPermission') ?? false;

  /// Triggers the system POST_NOTIFICATIONS dialog and resolves to the
  /// resulting grant. Returns true immediately on pre-Android-13 devices.
  static Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;

  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
      false;

  /// Opens the system battery-optimization exemption dialog. Fire-and-forget
  /// — re-check [isIgnoringBatteryOptimizations] when the app resumes.
  static Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
}
