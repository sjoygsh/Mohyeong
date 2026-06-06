/// Download-manager preferences exposed under Settings → Downloads.
/// Keys mirror the Kotlin `DownloadPreferences` names so a settings
/// import carries values across without translation.
///
/// [downloadSlotsProvider] is consumed by the download queue's drain loop
/// (reads `download_slots` for concurrency). The auto-download family
/// ([downloadNewChaptersProvider] + [downloadNewUnreadChaptersOnlyProvider]
/// + the category include/exclude sets) is wired into the library updater
/// via `FilterChaptersForDownload`. Wi-Fi-only ([downloadOnlyOverWifiProvider])
/// gates the queue drain loop, the remove-after-read family hooks the
/// read-path via `SetReadStatus`, CBZ ([saveChaptersAsCbzProvider]) is applied
/// at finalize time, and [autoDownloadWhileReadingProvider] drives the reader's
/// download-ahead. Split-tall ([splitTallImagesProvider]) is persisted but its
/// image-slicing pipeline is not yet wired.
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

/// When auto-downloading new chapters, skip chapters whose number is
/// already marked read elsewhere in the series.
final downloadNewUnreadChaptersOnlyProvider =
    boolPref('download_new_unread_chapters_only', false);

/// Category ids (as strings) whose manga are eligible for auto-download.
/// Empty = all categories eligible (subject to [downloadNewCategoriesExcludeProvider]).
final downloadNewCategoriesProvider =
    stringSetPref('download_new_categories', const {});

/// Category ids (as strings) whose manga are excluded from auto-download,
/// taking precedence over [downloadNewCategoriesProvider].
final downloadNewCategoriesExcludeProvider =
    stringSetPref('download_new_categories_exclude', const {});

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

/// Number of chapters to keep downloaded ahead of the one currently being
/// read. 0 disables download-ahead. Consumed by the reader, which enqueues
/// the next unread chapters once you pass 25% of a downloaded chapter.
final autoDownloadWhileReadingProvider =
    intPref('auto_download_while_reading', 0);
