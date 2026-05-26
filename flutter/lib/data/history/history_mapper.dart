import '../database/app_database.dart' as db;
import '../../domain/history/model/history.dart';

class HistoryMapper {
  const HistoryMapper._();

  /// last_read in the DB is INTEGER epoch-millis (matches Kotlin's
  /// `AS Date` adapter which serialised Date.time on write). Null → null.
  static History fromRow(db.HistoryData row) => History(
        id: row.id,
        chapterId: row.chapterId,
        readAt: row.lastRead == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.lastRead!),
        readDuration: row.timeRead,
      );
}
