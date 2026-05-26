import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart' as db;
import '../../domain/chapter/model/chapter.dart';

class ChapterMapper {
  const ChapterMapper._();

  static Chapter fromRow(db.Chapter row) => Chapter(
        id: row.id,
        mangaId: row.mangaId,
        read: row.read != 0,
        bookmark: row.bookmark != 0,
        lastPageRead: row.lastPageRead,
        dateFetch: row.dateFetch,
        sourceOrder: row.sourceOrder,
        url: row.url,
        name: row.name,
        dateUpload: row.dateUpload,
        chapterNumber: row.chapterNumber,
        scanlator: row.scanlator,
        lastModifiedAt: row.lastModifiedAt,
        version: row.version,
        bookmarkNote: row.bookmarkNote,
        volumeNumber: row.volumeNumber,
      );

  static db.ChaptersCompanion toCompanion(Chapter chapter) {
    return db.ChaptersCompanion.insert(
      id: Value(chapter.id),
      mangaId: chapter.mangaId,
      url: chapter.url,
      name: chapter.name,
      scanlator: Value(chapter.scanlator),
      read: chapter.read ? 1 : 0,
      bookmark: chapter.bookmark ? 1 : 0,
      lastPageRead: chapter.lastPageRead,
      chapterNumber: chapter.chapterNumber,
      sourceOrder: chapter.sourceOrder,
      dateFetch: chapter.dateFetch,
      dateUpload: chapter.dateUpload,
      lastModifiedAt: Value(chapter.lastModifiedAt),
      version: Value(chapter.version),
      isSyncing: const Value(0),
      bookmarkNote: Value(chapter.bookmarkNote),
      volumeNumber: Value(chapter.volumeNumber),
    );
  }
}
