import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    // Importances mirror Notifications.kt: progress/error channels are LOW
    // (silent, no badge), new-chapters is DEFAULT, complete is HIGH.
    const channels = <AndroidNotificationChannel>[
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
      ),
      AndroidNotificationChannel(
        channelLibraryError,
        'Library errors',
        importance: Importance.low,
        showBadge: false,
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
      ),
      AndroidNotificationChannel(
        channelDownloaderError,
        'Download errors',
        importance: Importance.low,
        showBadge: false,
      ),
      AndroidNotificationChannel(
        channelBackupRestoreProgress,
        'Backup/restore progress',
        importance: Importance.low,
        showBadge: false,
      ),
      AndroidNotificationChannel(
        channelBackupRestoreComplete,
        'Backup/restore complete',
        importance: Importance.high,
        showBadge: false,
        playSound: false,
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
      ),
      AndroidNotificationChannel(
        channelExtensionsUpdate,
        'Extension updates',
        importance: Importance.defaultImportance,
      ),
    ];
    for (final channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }

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
      title,
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
      title,
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
      title,
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
