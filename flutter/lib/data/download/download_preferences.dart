/// Download-manager preferences exposed under Settings → Downloads.
/// Keys mirror the Kotlin `DownloadPreferences` names so a settings
/// import carries values across without translation.
///
/// Only [downloadSlotsProvider] is consumed today — the download queue's
/// drain loop reads `download_slots` to decide how many chapters to fetch
/// concurrently. The remaining toggles are persisted and surfaced in the
/// settings UI but their behaviour is not yet wired (see the progress
/// notes): wifi-only needs a connectivity plugin, CBZ/split-tall need an
/// archive/image pipeline, and the auto-download / remove-after-read
/// flows need hooks into the library updater and read path.
library;

import '../preferences/typed_preferences.dart';

/// Number of chapters the download queue fetches in parallel (1..5).
/// Read by `DownloadRepository` at drain time.
final downloadSlotsProvider = intPref('download_slots', 1);

/// Restrict downloads to unmetered (Wi-Fi) connections.
final downloadOnlyOverWifiProvider =
    boolPref('pref_download_only_over_wifi_key', true);

/// Automatically download new chapters as they're discovered by a
/// library update.
final downloadNewChaptersProvider = boolPref('download_new', false);

/// Delete a chapter's download once it's marked read.
final removeAfterMarkedAsReadProvider =
    boolPref('pref_remove_after_marked_as_read_key', false);

/// How many read chapters to keep downloaded behind the current one.
/// -1 = never auto-remove; 0 = remove as soon as read; N = keep N.
final removeAfterReadSlotsProvider = intPref('remove_after_read_slots', -1);

/// Exclude bookmarked chapters from any auto-removal.
final removeBookmarkedChaptersProvider =
    boolPref('pref_remove_bookmarked_chapters', false);

/// Archive each downloaded chapter as a single CBZ file instead of a
/// folder of page images.
final saveChaptersAsCbzProvider = boolPref('save_chapter_as_cbz', false);

/// Split tall (webtoon-strip) images into screen-height slices on
/// download for smoother paging.
final splitTallImagesProvider = boolPref('split_tall_images', false);
