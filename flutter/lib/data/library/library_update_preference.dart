import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../preferences/typed_preferences.dart';

/// User-facing choice for how often the background library updater fires.
/// Matches the option list shown in Mihon's settings.
///
/// Values are persisted as `int` hours so the value itself is the recurrence
/// interval passed to workmanager. `0` means "manual only" — no scheduled
/// work.
enum LibraryUpdateInterval {
  // Labels copied verbatim from Kotlin (`update_never`/`update_12hour`/… ).
  manual(0, 'Off'),
  every12h(12, 'Every 12 hours'),
  daily(24, 'Daily'),
  every48h(48, 'Every 2 days'),
  every72h(72, 'Every 3 days'),
  weekly(168, 'Weekly');

  const LibraryUpdateInterval(this.hours, this.label);

  final int hours;
  final String label;

  static LibraryUpdateInterval fromHours(int hours) {
    for (final v in values) {
      if (v.hours == hours) return v;
    }
    return LibraryUpdateInterval.daily;
  }
}

class LibraryUpdatePreferenceNotifier
    extends Notifier<LibraryUpdateInterval> {
  // Key carefully chosen to be migration-friendly with the Kotlin app's
  // `pref_library_update_interval_key` once we wire up a migration step.
  static const _key = 'pref_library_update_interval_hours';

  @override
  LibraryUpdateInterval build() {
    _loadFromDisk();
    return LibraryUpdateInterval.daily;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    if (stored == null) return;
    final loaded = LibraryUpdateInterval.fromHours(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> setInterval(LibraryUpdateInterval interval) async {
    state = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, interval.hours);
  }
}

final libraryUpdatePreferenceProvider =
    NotifierProvider<LibraryUpdatePreferenceNotifier, LibraryUpdateInterval>(
  LibraryUpdatePreferenceNotifier.new,
);

/// Per-manga "smart update" restriction tokens. Mirrors the string values
/// Mihon stores in the `library_update_manga_restriction` set so the
/// preference is interoperable on a future settings import.
abstract final class MangaUpdateRestriction {
  /// Skip a manga that still has unread chapters ("not caught up").
  static const hasUnread = 'manga_fully_read';

  /// Skip a manga whose source status is "Completed".
  static const nonCompleted = 'manga_ongoing';

  /// Skip a manga the user hasn't started reading yet.
  static const nonRead = 'manga_started';

  /// Skip a manga whose projected next release is still in the future.
  static const outsideReleasePeriod = 'manga_outside_release_period';
}

/// The "Smart update" restriction set (Settings → Library). Defaults to all
/// four restrictions on, matching Mihon's `autoUpdateMangaRestrictions`.
final libraryUpdateMangaRestrictionProvider = stringSetPref(
  'library_update_manga_restriction',
  const {
    MangaUpdateRestriction.hasUnread,
    MangaUpdateRestriction.nonCompleted,
    MangaUpdateRestriction.nonRead,
    MangaUpdateRestriction.outsideReleasePeriod,
  },
);

/// Device-state restrictions on the background library update, mirroring
/// Kotlin's `autoUpdateDeviceRestrictions` set. Tokens match the Kotlin
/// `LibraryPreferences.DEVICE_*` constants so a settings import carries over.
/// Read by [LibraryUpdateScheduler] when building the workmanager
/// `Constraints`. Defaults to Wi-Fi-only, matching Mihon.
abstract final class DeviceRestriction {
  /// Only run while connected to an unmetered (typically Wi-Fi) network.
  static const onlyOnWifi = 'wifi';

  /// Only run on a network the OS reports as not metered.
  static const networkNotMetered = 'network_not_metered';

  /// Only run while the device is charging.
  static const charging = 'ac';
}

/// The active device-restriction set (Settings → Library → Global update).
final libraryUpdateDeviceRestrictionProvider = stringSetPref(
  'library_update_restriction',
  const {DeviceRestriction.onlyOnWifi},
);

/// "Automatically refresh metadata" — when on, the library sweep also pulls
/// fresh manga details (cover/description/status) per entry, not just the
/// chapter list. Mirrors Kotlin's `autoUpdateMetadata` (default false).
final autoUpdateMetadataProvider =
    boolPref('auto_update_metadata', false);

/// Tokens of the "Mark duplicate read chapter as read" multi-select
/// (Kotlin `MARK_DUPLICATE_CHAPTER_READ_*`).
abstract final class MarkDuplicateRead {
  /// Mark an existing unread duplicate read after reading a chapter.
  static const readExisting = 'existing';

  /// Mark a newly fetched chapter read when a read duplicate exists.
  static const readNew = 'new';
}

/// "Mark duplicate read chapter as read" (Settings → Library → Behavior).
/// Mihon `markDuplicateReadChapterAsRead`, default empty (off).
final markDuplicateReadChapterAsReadProvider =
    stringSetPref('mark_duplicate_read_chapter_read', const {});

/// "Clear chapter cache on app launch" (Data and storage). Mihon
/// `autoClearChapterCache`, key `auto_clear_chapter_cache`, default false.
final autoClearChapterCacheProvider =
    boolPref('auto_clear_chapter_cache', false);

/// Category newly-favourited manga land in (Settings → Library →
/// "Default category"). Mihon `LibraryPreferences.defaultCategory`, key
/// `default_category`: -1 = "Always ask" (category sheet on favourite),
/// 0 = the system Default category (no explicit membership), otherwise a
/// user category id.
final defaultCategoryProvider = intPref('default_category', -1);

/// "Show unread count on Updates icon" (Settings → Library). Gates the
/// bottom-nav Updates badge. Mihon `newShowUpdatesCount`,
/// key `library_show_updates_count`, default true.
final newShowUpdatesCountProvider =
    boolPref('library_show_updates_count', true);

/// Running count of chapters found by library updates that the user hasn't
/// looked at yet — the number on the Updates nav badge. Incremented by the
/// updater per new chapter, reset to 0 when the Updates tab is opened.
/// Mihon `newUpdatesCount`, app-state key (excluded from backups).
final newUpdatesCountProvider =
    intPref('__APP_STATE_library_unseen_updates_count', 0);

/// Categories to include in the global library update (empty = all).
final libraryUpdateCategoriesProvider =
    stringSetPref('library_update_categories', const {});

/// Categories to exclude from the global library update. Exclusion wins over
/// inclusion.
final libraryUpdateCategoriesExcludeProvider =
    stringSetPref('library_update_categories_exclude', const {});
