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
    // An unrecognised stored value must not silently start updating either.
    return LibraryUpdateInterval.manual;
  }
}

class LibraryUpdatePreferenceNotifier
    extends Notifier<LibraryUpdateInterval> {
  static const _key = 'pref_library_update_interval_hours';

  /// The Kotlin fork's spelling of the same value.
  ///
  /// It stores hours under `pref_library_update_interval_key` with exactly
  /// these numbers, 0 included, so the two are value-compatible and only the
  /// name differs. The v0.19 → v1.0 upgrade happens in place under the same
  /// applicationId, so those preferences are still sitting in the same store
  /// — this key was chosen to be "migration-friendly … once we wire up a
  /// migration step", and that step was never wired. Until now the interval
  /// silently fell back to the Flutter default on upgrade, which for someone
  /// who had set it to Off meant the library started updating itself.
  static const _legacyKey = 'pref_library_update_interval_key';

  /// The fork's default is 0 — Off (`autoUpdateInterval` in
  /// `LibraryPreferences.kt`). This defaulted to `daily`, which no comment
  /// justified and which no sibling default did: a fresh install, or an
  /// in-place upgrade from someone who had never opened the setting, started
  /// sweeping the whole library once a day without being asked. Combined with
  /// the flat download drain (pass 26) that is a lot of unrequested traffic to
  /// sources that answer load with 403s.
  @override
  LibraryUpdateInterval build() {
    _loadFromDisk();
    return LibraryUpdateInterval.manual;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key) ?? prefs.getInt(_legacyKey);
    if (stored == null) return;
    final loaded = LibraryUpdateInterval.fromHours(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> setInterval(LibraryUpdateInterval interval) async {
    state = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, interval.hours);
    // Once the value lives under our own key, drop the fork's copy so the
    // two can never disagree.
    await prefs.remove(_legacyKey);
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

// Mihon's `newShowUpdatesCount` (`library_show_updates_count`) and
// `newUpdatesCount` (`__APP_STATE_library_unseen_updates_count`) have no
// providers here. Both existed to badge the Updates tab with a count of
// unseen chapters; this build folded Updates into the home feed's Tonight
// section and deleted the tab along with the nav bar that carried it. The
// toggle had no icon left to gate and the counter had no reader — the sweep
// was incrementing a number nothing displayed.

/// Categories to include in the global library update (empty = all).
final libraryUpdateCategoriesProvider =
    stringSetPref('library_update_categories', const {});

/// Categories to exclude from the global library update. Exclusion wins over
/// inclusion.
final libraryUpdateCategoriesExcludeProvider =
    stringSetPref('library_update_categories_exclude', const {});
