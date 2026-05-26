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
      id: Value(track.id),
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
