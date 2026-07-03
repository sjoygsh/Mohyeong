import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart' as db;
import '../../domain/track/model/track.dart';

class TrackMapper {
  const TrackMapper._();

  static Track fromRow(db.MangaSyncData row) => Track(
        id: row.id,
        mangaId: row.mangaId,
        trackerId: row.syncId,
        remoteId: row.remoteId,
        libraryId: row.libraryId,
        title: row.title,
        lastChapterRead: row.lastChapterRead,
        totalChapters: row.totalChapters,
        status: row.status,
        score: row.score,
        remoteUrl: row.remoteUrl,
        startDate: row.startDate,
        finishDate: row.finishDate,
        private: row.private != 0,
      );

  static db.MangaSyncCompanion toCompanion(Track track) {
    return db.MangaSyncCompanion.insert(
      // Sentinel ids must NOT be written literally: the PK-targeted upsert
      // would collapse every new track onto the single sentinel row,
      // clobbering the previous manga's binding. There are TWO sentinels in
      // the wild — bind flows and backup restore build tracks with -1, the
      // migration service copies with id 0 — hence <= 0, not < 0. Absent →
      // autoincrement; a real (manga, tracker) duplicate is handled by the
      // table's UNIQUE ON CONFLICT REPLACE.
      id: track.id <= 0 ? const Value.absent() : Value(track.id),
      mangaId: track.mangaId,
      syncId: track.trackerId,
      remoteId: track.remoteId,
      libraryId: Value(track.libraryId),
      title: track.title,
      lastChapterRead: track.lastChapterRead,
      totalChapters: track.totalChapters,
      status: track.status,
      score: track.score,
      remoteUrl: track.remoteUrl,
      startDate: track.startDate,
      finishDate: track.finishDate,
      private: Value(track.private ? 1 : 0),
    );
  }
}
