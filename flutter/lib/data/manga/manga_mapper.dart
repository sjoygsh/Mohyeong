import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart' as db;
import '../../domain/manga/model/manga.dart';
import '../../domain/manga/model/update_strategy.dart';

/// Translates Drift's generated `Manga` row class (alias `db.Manga`) into the
/// domain `Manga` and back. Equivalent to the Kotlin `MangaMapper` object.
///
/// The DB stores genre as a comma-separated TEXT column; the Kotlin layer
/// used SQLDelight's `AS List<String>` adapter to split/join. Here we do it
/// manually inside the mapper so domain code stays unaware of the encoding.
class MangaMapper {
  const MangaMapper._();

  static Manga fromRow(db.Manga row) => Manga(
        id: row.id,
        source: row.source,
        favorite: row.favorite != 0,
        lastUpdate: row.lastUpdate ?? 0,
        nextUpdate: row.nextUpdate ?? 0,
        // calculate_interval is INTEGER NOT NULL DEFAULT 0, so it's non-null
        // out of Drift -- no fallback needed.
        fetchInterval: row.calculateInterval,
        dateAdded: row.dateAdded,
        viewerFlags: row.viewer,
        chapterFlags: row.chapterFlags,
        coverLastModified: row.coverLastModified,
        url: row.url,
        title: row.title,
        artist: row.artist,
        author: row.author,
        description: row.description,
        genre: _splitGenre(row.genre),
        status: row.status,
        thumbnailUrl: row.thumbnailUrl,
        updateStrategy: UpdateStrategy.fromDb(row.updateStrategy),
        initialized: row.initialized != 0,
        lastModifiedAt: row.lastModifiedAt,
        favoriteModifiedAt: row.favoriteModifiedAt,
        version: row.version,
        notes: row.notes,
      );

  static db.MangasCompanion toCompanion(Manga manga) {
    return db.MangasCompanion.insert(
      id: Value(manga.id),
      source: manga.source,
      url: manga.url,
      artist: Value(manga.artist),
      author: Value(manga.author),
      description: Value(manga.description),
      genre: Value(_joinGenre(manga.genre)),
      title: manga.title,
      status: manga.status,
      thumbnailUrl: Value(manga.thumbnailUrl),
      favorite: manga.favorite ? 1 : 0,
      lastUpdate: Value(manga.lastUpdate),
      nextUpdate: Value(manga.nextUpdate),
      initialized: manga.initialized ? 1 : 0,
      viewer: manga.viewerFlags,
      chapterFlags: manga.chapterFlags,
      coverLastModified: manga.coverLastModified,
      dateAdded: manga.dateAdded,
      updateStrategy: Value(manga.updateStrategy.dbValue),
      calculateInterval: Value(manga.fetchInterval),
      lastModifiedAt: Value(manga.lastModifiedAt),
      favoriteModifiedAt: Value(manga.favoriteModifiedAt),
      version: Value(manga.version),
      // is_syncing is a per-write flag controlled by the sync subsystem, not
      // a domain concept. Mapper writes always set it to 0 -- sync paths use
      // a dedicated method that toggles it manually for the duration of the
      // batch.
      isSyncing: const Value(0),
      notes: Value(manga.notes),
    );
  }

  /// Comma-split with empty-input handling, matching SQLDelight's
  /// `List<String>` column adapter.
  static List<String>? _splitGenre(String? raw) {
    if (raw == null) return null;
    if (raw.isEmpty) return const [];
    return raw.split(',');
  }

  static String? _joinGenre(List<String>? genre) {
    if (genre == null) return null;
    return genre.join(',');
  }
}
