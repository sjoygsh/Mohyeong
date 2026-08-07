import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/notification/notification_service.dart';

/// Android notification channels live in the OS, not the APK, and the
/// v0.19 → v1.0 upgrade keeps the same applicationId — so an upgraded device
/// still carries every channel the Kotlin build ever registered, including
/// the ones it stopped using. Kotlin deletes those on each start; so must we,
/// or they sit in the app's notification settings as switches that do
/// nothing.
///
/// The subtle part: Kotlin's own deprecated list contains
/// `library_progress_channel` and then recreates it two statements later.
/// That id is live here, so porting the list verbatim would delete a channel
/// in use on every launch and reset whatever the user had set on it.
///
/// The plugin cannot initialise on a host VM (it resolves its Android
/// implementation through `dart:io`), so this pins the declarations rather
/// than the calls — which is where the mistake would be anyway.
void main() {
  test('the deprecated list never names a channel we still register', () {
    final live = {for (final c in NotificationService.channels) c.id};
    for (final id in NotificationService.deprecatedChannels) {
      expect(live, isNot(contains(id)),
          reason: '$id is registered AND marked deprecated');
    }
  });

  test('it does name the ones the Kotlin build left behind', () {
    expect(
      NotificationService.deprecatedChannels,
      containsAll(<String>[
        'downloader_channel',
        'downloader_complete_channel',
        'backup_restore_complete_channel',
        'library_channel',
        'updates_ext_channel',
        'downloader_cache_renewal',
        'crash_logs_channel',
        'library_skipped_channel',
      ]),
    );
    // The one Kotlin lists that we must keep.
    expect(NotificationService.deprecatedChannels,
        isNot(contains(NotificationService.channelLibraryProgress)));
  });

  test('every groupId a channel names is a group we declare', () {
    final declared = {for (final g in NotificationService.groups) g.id};
    for (final c in NotificationService.channels) {
      if (c.groupId == null) continue;
      expect(declared, contains(c.groupId),
          reason: '${c.id} points at a group that is never created');
    }
  });

  test('channels are grouped the way the fork groups them', () {
    String? groupOf(String id) => NotificationService.channels
        .firstWhere((c) => c.id == id)
        .groupId;

    expect(groupOf(NotificationService.channelLibraryProgress),
        'group_library');
    expect(groupOf(NotificationService.channelLibraryError), 'group_library');
    expect(groupOf(NotificationService.channelDownloaderProgress),
        'group_downloader');
    expect(groupOf(NotificationService.channelDownloaderError),
        'group_downloader');
    expect(groupOf(NotificationService.channelBackupRestoreProgress),
        'group_backup_restore');
    expect(groupOf(NotificationService.channelBackupRestoreComplete),
        'group_backup_restore');
    expect(groupOf(NotificationService.channelAppUpdate), 'group_apk_updates');
    expect(groupOf(NotificationService.channelExtensionsUpdate),
        'group_apk_updates');

    // Ungrouped in the fork too — no `setGroup` on these three.
    expect(groupOf(NotificationService.channelCommon), isNull);
    expect(groupOf(NotificationService.channelNewChapters), isNull);
    expect(groupOf(NotificationService.channelIncognito), isNull);
  });

  test('importances still match Notifications.kt', () {
    Importance importanceOf(String id) => NotificationService.channels
        .firstWhere((c) => c.id == id)
        .importance;

    expect(importanceOf(NotificationService.channelLibraryProgress),
        Importance.low);
    expect(importanceOf(NotificationService.channelNewChapters),
        Importance.defaultImportance);
    expect(importanceOf(NotificationService.channelBackupRestoreComplete),
        Importance.high);
  });
}
