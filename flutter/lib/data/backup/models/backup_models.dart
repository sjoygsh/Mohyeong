/// Dart mirrors of Mihon's `eu.kanade.tachiyomi.data.backup.models.*` classes.
///
/// These are **wire-format compatible** with Mihon's
/// kotlinx.serialization-protobuf encoding: every field carries the same
/// `ProtoNumber` tag as the corresponding Kotlin field, the same primitive
/// type (int32 / int64 / float / double / string / bool / repeated), and the
/// same default value. A backup file produced by Mihon must decode into
/// these models without loss and re-encode to a byte-identical payload.
///
/// Field numbers (and quirks like "sourceOrder is negated on the wire",
/// the deprecated `mediaIdInt`, or `volumeNumber` being `double?`) are
/// drawn from the Kotlin sources at
/// `app/src/main/java/eu/kanade/tachiyomi/data/backup/models/`.
library;

// ─── Top-level Backup ──────────────────────────────────────────────────────

/// Mirror of `Backup.kt`. Single root message of every backup file.
class Backup {
  Backup({
    this.backupManga = const [],
    this.backupCategories = const [],
    this.backupSources = const [],
    this.backupPreferences = const [],
    this.backupSourcePreferences = const [],
    this.backupExtensionRepo = const [],
    this.backupMangaLinks = const [],
  });

  /// tag 1 — list of all favorited manga (and their chapters, history,
  /// tracking, ...). Empty list is encoded as zero-length, never missing.
  final List<BackupManga> backupManga;

  /// tag 2 — every category the user defined, including "Default" (id 0).
  final List<BackupCategory> backupCategories;

  /// tag 101 — minimal `(sourceId, name)` table so a backup remains
  /// readable even after the extension that produced an entry is gone.
  final List<BackupSource> backupSources;

  /// tag 104 — app-wide preferences (Settings → Appearance, Library, ...).
  final List<BackupPreference> backupPreferences;

  /// tag 105 — per-source preference snapshots.
  final List<BackupSourcePreferences> backupSourcePreferences;

  /// tag 106 — saved third-party extension repos.
  final List<BackupExtensionRepos> backupExtensionRepo;

  /// tag 107 — Mihon's "Linked manga" feature (one library entry pointing
  /// at multiple sources). Preserved for round-trip even though Mohyeong
  /// v1.0 doesn't surface a linking UI yet.
  final List<BackupMangaLink> backupMangaLinks;
}

// ─── BackupManga ───────────────────────────────────────────────────────────

/// Mirror of `BackupManga.kt`. Note the non-contiguous tag numbers — 10/11/
/// 12/15 are intentionally gone (deprecated fields in Mihon's history).
class BackupManga {
  BackupManga({
    required this.source,
    required this.url,
    this.title = '',
    this.artist,
    this.author,
    this.description,
    this.genre = const [],
    this.status = 0,
    this.thumbnailUrl,
    this.dateAdded = 0,
    this.viewer = 0,
    this.chapters = const [],
    this.categories = const [],
    this.tracking = const [],
    this.favorite = true,
    this.chapterFlags = 0,
    this.viewerFlags,
    this.history = const [],
    this.updateStrategy = 0, // UpdateStrategy.ALWAYS_UPDATE
    this.lastModifiedAt = 0,
    this.favoriteModifiedAt,
    this.excludedScanlators = const [],
    this.version = 0,
    this.notes = '',
    this.initialized = false,
  });

  /// tag 1 — `sourceId` (Long).
  final int source;

  /// tag 2 — opaque, source-specific manga URL/key.
  final String url;

  /// tag 3.
  final String title;

  /// tag 4.
  final String? artist;

  /// tag 5.
  final String? author;

  /// tag 6.
  final String? description;

  /// tag 7 — repeated string.
  final List<String> genre;

  /// tag 8 — Mihon's `SManga.status` constant.
  final int status;

  /// tag 9.
  final String? thumbnailUrl;

  /// tag 13 — epoch millis.
  final int dateAdded;

  /// tag 14 — per-manga reader viewer override (0 = inherit global).
  final int viewer;

  /// tag 16 — repeated.
  final List<BackupChapter> chapters;

  /// tag 17 — repeated. Indices into the `backupCategories` list at the
  /// root (NOT category IDs).
  final List<int> categories;

  /// tag 18 — repeated.
  final List<BackupTracking> tracking;

  /// tag 100 — default `true` because every backed-up entry is in the
  /// library at the moment of capture.
  final bool favorite;

  /// tag 101.
  final int chapterFlags;

  /// tag 102 — nullable; older backups omit this.
  final int? viewerFlags;

  /// tag 103.
  final List<BackupHistory> history;

  /// tag 104 — `Manga.UpdateStrategy` ordinal.
  final int updateStrategy;

  /// tag 105.
  final int lastModifiedAt;

  /// tag 106 — nullable, used by Mihon's sync diffing.
  final int? favoriteModifiedAt;

  /// tag 107.
  final List<String> excludedScanlators;

  /// tag 108.
  final int version;

  /// tag 110.
  final String notes;

  /// tag 111.
  final bool initialized;
}

// ─── BackupChapter ─────────────────────────────────────────────────────────

class BackupChapter {
  BackupChapter({
    required this.url,
    this.name = '',
    this.scanlator,
    this.read = false,
    this.bookmark = false,
    this.lastPageRead = 0,
    this.dateFetch = 0,
    this.dateUpload = 0,
    this.chapterNumber = -1.0,
    this.sourceOrder = 0,
    this.lastModifiedAt = 0,
    this.version = 0,
    this.bookmarkNote = '',
    this.volumeNumber,
  });

  /// tag 1.
  final String url;

  /// tag 2.
  final String name;

  /// tag 3.
  final String? scanlator;

  /// tag 4.
  final bool read;

  /// tag 5.
  final bool bookmark;

  /// tag 6.
  final int lastPageRead;

  /// tag 7 — epoch millis when Mihon first saw the chapter.
  final int dateFetch;

  /// tag 8 — epoch millis from the source (publication date).
  final int dateUpload;

  /// tag 9 — `Float` on Mihon's side; preserve precision via `double` in
  /// Dart but encode as a 32-bit float on the wire.
  final double chapterNumber;

  /// tag 10 — Mihon stores `(0 - sourceOrder)` here; we hand back the
  /// negated value untouched so a round-trip is exact.
  final int sourceOrder;

  /// tag 11.
  final int lastModifiedAt;

  /// tag 12.
  final int version;

  /// tag 13.
  final String bookmarkNote;

  /// tag 14 — `Double?` in Kotlin.
  final double? volumeNumber;
}

// ─── BackupCategory ────────────────────────────────────────────────────────

class BackupCategory {
  BackupCategory({
    required this.name,
    this.order = 0,
    this.id = 0,
    this.flags = 0,
    this.parentId,
  });

  /// tag 1.
  final String name;

  /// tag 2 — `Long` (sort order within siblings).
  final int order;

  /// tag 3.
  final int id;

  /// tag 100 — `Long` library display/sort flags bitmask.
  final int flags;

  /// tag 101 — `Long?`. Nested categories (parent != null).
  final int? parentId;
}

// ─── BackupHistory ─────────────────────────────────────────────────────────

class BackupHistory {
  BackupHistory({
    required this.url,
    required this.lastRead,
    this.readDuration = 0,
  });

  /// tag 1 — chapter URL (matches BackupChapter.url).
  final String url;

  /// tag 2 — epoch millis.
  final int lastRead;

  /// tag 3 — total time spent reading the chapter, in millis.
  final int readDuration;
}

// ─── BackupTracking ────────────────────────────────────────────────────────

class BackupTracking {
  BackupTracking({
    required this.syncId,
    this.libraryId,
    this.mediaIdInt = 0,
    this.trackingUrl = '',
    this.title = '',
    this.lastChapterRead = 0.0,
    this.totalChapters = 0,
    this.score = 0.0,
    this.status = 0,
    this.startedReadingDate = 0,
    this.finishedReadingDate = 0,
    this.private = false,
    this.mediaId = 0,
  });

  /// tag 1 — `trackerId` (matches our `TrackerIds`).
  final int syncId;

  /// tag 2 — `Long?` — remote user's list entry id (AniList list_id, ...).
  final int? libraryId;

  /// tag 3 — **deprecated**. Mihon kept this as `Int` for backwards-
  /// compat with very old backups. Always 0 on new exports.
  @Deprecated('Mihon writes 0 here; real id lives in `mediaId` (tag 100)')
  final int mediaIdInt;

  /// tag 4.
  final String trackingUrl;

  /// tag 5.
  final String title;

  /// tag 6 — `Float`.
  final double lastChapterRead;

  /// tag 7.
  final int totalChapters;

  /// tag 8 — `Float`.
  final double score;

  /// tag 9 — Mihon `TrackerManager` status constant (per-tracker).
  final int status;

  /// tag 10 — epoch millis.
  final int startedReadingDate;

  /// tag 11 — epoch millis.
  final int finishedReadingDate;

  /// tag 12.
  final bool private;

  /// tag 100 — `Long`. Tag 100 (not 13) because Mihon migrated the field
  /// after the original `Int` overflowed for some trackers.
  final int mediaId;
}

// ─── BackupSource ──────────────────────────────────────────────────────────

class BackupSource {
  BackupSource({required this.name, required this.sourceId});

  /// tag 1.
  final String name;

  /// tag 2 — `Long`.
  final int sourceId;
}

// ─── BackupPreference + value union ────────────────────────────────────────

class BackupPreference {
  BackupPreference({required this.key, required this.value});

  /// tag 1.
  final String key;

  /// tag 2 — sealed class on the Kotlin side.
  final BackupPreferenceValue value;
}

class BackupSourcePreferences {
  BackupSourcePreferences({required this.sourceKey, this.prefs = const []});

  /// tag 1 — the source's stable key (usually the source id).
  final String sourceKey;

  /// tag 2.
  final List<BackupPreference> prefs;
}

/// Sealed-equivalent. Each subclass corresponds to one of Mihon's
/// `PreferenceValue` variants and carries the same protobuf "oneof"
/// discriminator number that Mihon assigns. Mihon uses
/// `@Serializable(with = ...)` polymorphism where the wire tag of the
/// **field** distinguishes the variant — see `BackupPreferenceSerializer`.
sealed class BackupPreferenceValue {
  const BackupPreferenceValue();
}

class IntPreferenceValue extends BackupPreferenceValue {
  const IntPreferenceValue(this.value);
  final int value;
}

class LongPreferenceValue extends BackupPreferenceValue {
  const LongPreferenceValue(this.value);
  final int value;
}

class FloatPreferenceValue extends BackupPreferenceValue {
  const FloatPreferenceValue(this.value);
  final double value;
}

class StringPreferenceValue extends BackupPreferenceValue {
  const StringPreferenceValue(this.value);
  final String value;
}

class BooleanPreferenceValue extends BackupPreferenceValue {
  const BooleanPreferenceValue(this.value);
  final bool value;
}

class StringSetPreferenceValue extends BackupPreferenceValue {
  const StringSetPreferenceValue(this.value);
  final Set<String> value;
}

// ─── BackupMangaLink ───────────────────────────────────────────────────────

class BackupMangaLink {
  BackupMangaLink({
    required this.primarySource,
    required this.primaryUrl,
    required this.linkedSource,
    required this.linkedUrl,
    this.priority = 0,
  });

  /// tag 1 — `Long`.
  final int primarySource;

  /// tag 2.
  final String primaryUrl;

  /// tag 3 — `Long`.
  final int linkedSource;

  /// tag 4.
  final String linkedUrl;

  /// tag 5.
  final int priority;
}

// ─── BackupExtensionRepos ──────────────────────────────────────────────────

class BackupExtensionRepos {
  BackupExtensionRepos({
    required this.baseUrl,
    required this.name,
    required this.shortName,
    required this.website,
    required this.signingKeyFingerprint,
  });

  /// tag 1.
  final String baseUrl;

  /// tag 2.
  final String name;

  /// tag 3.
  final String shortName;

  /// tag 4.
  final String website;

  /// tag 5.
  final String signingKeyFingerprint;
}
