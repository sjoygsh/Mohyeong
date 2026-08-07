import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central notification surface, ported from the Kotlin `Notifications` object
/// plus the per-feature `*Notifier` classes. Channel ids and notification ids
/// mirror Mihon verbatim (see `Notifications.kt`) so behaviour — grouping,
/// importance, and which notification replaces which — matches the Kotlin app.
///
/// Usable from both the UI isolate and the workmanager background isolate: the
/// library-update sweep runs in a fresh isolate with no Riverpod, so this is a
/// plain singleton with an idempotent [init] rather than a provider.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  // --- Channel ids (verbatim Mihon keys). ---
  static const channelCommon = 'common_channel';
  static const channelLibraryProgress = 'library_progress_channel';
  static const channelLibraryError = 'library_errors_channel';
  static const channelNewChapters = 'new_chapters_channel';
  static const channelDownloaderProgress = 'downloader_progress_channel';
  static const channelDownloaderError = 'downloader_error_channel';
  static const channelBackupRestoreProgress =
      'backup_restore_progress_channel';
  static const channelBackupRestoreComplete =
      'backup_restore_complete_channel_v2';
  static const channelIncognito = 'incognito_mode_channel';
  static const channelAppUpdate = 'app_apk_update_channel';
  static const channelExtensionsUpdate = 'ext_apk_update_channel';

  // --- Notification ids (verbatim Mihon ids; negative ids are fine). ---
  static const idLibraryProgress = -101;
  static const idLibraryError = -102;
  static const idNewChapters = -301;
  static const idDownloadProgress = -201;
  static const idDownloadError = -202;
  static const idBackupProgress = -501;
  static const idBackupComplete = -502;
  static const idRestoreProgress = -503;
  static const idRestoreComplete = -504;
  static const idIncognito = -701;
  static const idAppUpdatePrompt = 2;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  /// Initialises the plugin and (re)creates every channel. Idempotent — safe
  /// to call from app start and again from the background isolate.
  Future<void> init() async {
    if (_initialised) return;
    // The Kotlin app's baseline setSmallIcon is R.drawable.ic_mihon — its
    // white-alpha Mohyeong glyph — not the full-colour launcher mipmap.
    const android = AndroidInitializationSettings('@drawable/ic_mihon');
    await _plugin.initialize(
      const InitializationSettings(android: android),
    );
    await _createChannels();
    _initialised = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Whether the user asked for manga titles to be kept off the lock screen
  /// (Settings → Security → "Hide notification content", Mihon key
  /// `hide_notification_content`).
  ///
  /// Read by key rather than through `securityPreferences` because the
  /// library sweep and the downloader both post from the workmanager isolate,
  /// where there is no Riverpod container — the same reason
  /// `LibraryUpdater` reads `auto_update_metadata` this way. Redaction
  /// follows Kotlin's notifiers: the generic progress/summary line stays, only
  /// the title is dropped, so a hidden notification is still informative.
  Future<bool> _hideContent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hide_notification_content') ?? false;
  }

  /// Channels the Kotlin app created and then stopped using.
  ///
  /// Android channels live in the OS, not the APK, and the v0.19 -> v1.0
  /// upgrade keeps the same applicationId — so every channel that build ever
  /// registered is still on an upgraded device, including these. Kotlin
  /// deletes them on each start (`Notifications.deprecatedChannels`); without
  /// the same call they sit in the app's notification settings forever as
  /// switches that control nothing.
  @visibleForTesting
  static const deprecatedChannels = <String>[
    'downloader_channel',
    'downloader_complete_channel',
    'backup_restore_complete_channel',
    'library_channel',
    'updates_ext_channel',
    'downloader_cache_renewal',
    'crash_logs_channel',
    'library_skipped_channel',
  ];

  /// Channel groups, matching `Notifications.createChannels`. Eleven channels
  /// in one flat list is a wall; grouped, the settings screen reads as the
  /// four things the app actually does in the background.
  @visibleForTesting
  static const groups = <AndroidNotificationChannelGroup>[
    AndroidNotificationChannelGroup('group_library', 'Library'),
    AndroidNotificationChannelGroup('group_downloader', 'Downloads'),
    AndroidNotificationChannelGroup('group_backup_restore', 'Backup & restore'),
    AndroidNotificationChannelGroup('group_apk_updates', 'Updates'),
  ];

  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    for (final id in deprecatedChannels) {
      // `library_progress_channel` is deliberately NOT in this list even
      // though Kotlin lists it — we still use that id, and deleting a live
      // channel would drop the user's own settings for it.
      await android.deleteNotificationChannel(id);
    }
    for (final group in groups) {
      await android.createNotificationChannelGroup(group);
    }
    for (final channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }

  /// Every channel this app registers, in creation order.
  ///
  /// Importances mirror Notifications.kt: progress/error channels are LOW
  /// (silent, no badge), new-chapters is DEFAULT, complete is HIGH.
  static const channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      channelCommon,
      'Common',
      importance: Importance.low,
    ),
    AndroidNotificationChannel(
      channelLibraryProgress,
      'Library progress',
      importance: Importance.low,
      showBadge: false,
      groupId: 'group_library',
    ),
    AndroidNotificationChannel(
      channelLibraryError,
      'Library errors',
      importance: Importance.low,
      showBadge: false,
      groupId: 'group_library',
    ),
    AndroidNotificationChannel(
      channelNewChapters,
      'New chapters',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      channelDownloaderProgress,
      'Download progress',
      importance: Importance.low,
      showBadge: false,
      groupId: 'group_downloader',
    ),
    AndroidNotificationChannel(
      channelDownloaderError,
      'Download errors',
      importance: Importance.low,
      showBadge: false,
      groupId: 'group_downloader',
    ),
    AndroidNotificationChannel(
      channelBackupRestoreProgress,
      'Backup/restore progress',
      importance: Importance.low,
      showBadge: false,
      groupId: 'group_backup_restore',
    ),
    AndroidNotificationChannel(
      channelBackupRestoreComplete,
      'Backup/restore complete',
      importance: Importance.high,
      showBadge: false,
      playSound: false,
      groupId: 'group_backup_restore',
    ),
    AndroidNotificationChannel(
      channelIncognito,
      'Incognito mode',
      importance: Importance.low,
    ),
    AndroidNotificationChannel(
      channelAppUpdate,
      'App updates',
      importance: Importance.defaultImportance,
      groupId: 'group_apk_updates',
    ),
    AndroidNotificationChannel(
      channelExtensionsUpdate,
      'Extension updates',
      importance: Importance.defaultImportance,
      groupId: 'group_apk_updates',
    ),
  ];

  // --- Library update (mirrors LibraryUpdateNotifier). ---

  /// Ongoing progress notification with a determinate bar, updated as the
  /// sweep advances through the eligible manga. [current] is 0-based.
  Future<void> showLibraryProgress({
    required int current,
    required int total,
    required String title,
  }) async {
    await _plugin.show(
      idLibraryProgress,
      'Updating library',
      await _hideContent() ? null : title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelLibraryProgress,
          'Library progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          maxProgress: total,
          progress: current,
          indeterminate: total == 0,
        ),
      ),
    );
  }

  Future<void> cancelLibraryProgress() => _plugin.cancel(idLibraryProgress);

  /// Result notification shown once a sweep completes and added new chapters.
  Future<void> showNewChapters({
    required int mangaCount,
    required int chapterCount,
  }) async {
    if (chapterCount <= 0) return;
    final body = mangaCount == 1
        ? '$chapterCount new chapter${chapterCount == 1 ? '' : 's'}'
        : '$chapterCount new chapters across $mangaCount titles';
    await _plugin.show(
      idNewChapters,
      'New chapters found',
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelNewChapters,
          'New chapters',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Error notification shown when one or more sources failed during a sweep.
  Future<void> showLibraryErrors(int failedCount) async {
    if (failedCount <= 0) return;
    await _plugin.show(
      idLibraryError,
      'Library update errors',
      '$failedCount title${failedCount == 1 ? '' : 's'} failed to update',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelLibraryError,
          'Library errors',
          importance: Importance.low,
          priority: Priority.low,
        ),
      ),
    );
  }

  // --- Incognito mode (mirrors the persistent incognito notification). ---

  /// Persistent, non-dismissable notification shown while incognito mode is
  /// on, mirroring Mihon's `IncognitoModeService` reminder.
  Future<void> showIncognito() async {
    await _plugin.show(
      idIncognito,
      'Incognito mode',
      'Reading activity is not being recorded',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelIncognito,
          'Incognito mode',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
      ),
    );
  }

  Future<void> cancelIncognito() => _plugin.cancel(idIncognito);

  // --- Downloader (mirrors DownloadNotifier). ---

  Future<void> showDownloadProgress({
    required String title,
    required int downloaded,
    required int total,
  }) async {
    await _plugin.show(
      idDownloadProgress,
      'Downloading',
      // Kotlin swaps the "<manga> - <chapter>" line for the bare page count
      // when content is hidden rather than blanking it, so the notification
      // still shows the download moving.
      await _hideContent() ? '$downloaded/$total' : title,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelDownloaderProgress,
          'Download progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          showProgress: true,
          maxProgress: total,
          progress: downloaded,
          indeterminate: total == 0,
        ),
      ),
    );
  }

  Future<void> cancelDownloadProgress() => _plugin.cancel(idDownloadProgress);

  Future<void> showDownloadError(String title) async {
    await _plugin.show(
      idDownloadError,
      'Download error',
      await _hideContent() ? 'A chapter failed to download' : title,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelDownloaderError,
          'Download errors',
          importance: Importance.low,
          priority: Priority.low,
        ),
      ),
    );
  }

  // --- App update (mirrors AppUpdateNotifier prompt). ---

  Future<void> showAppUpdate(String version) async {
    await _plugin.show(
      idAppUpdatePrompt,
      'App update available',
      'Version $version is available to download',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelAppUpdate,
          'App updates',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
}
