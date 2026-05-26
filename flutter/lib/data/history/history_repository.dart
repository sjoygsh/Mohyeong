import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/history/model/history.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'history_mapper.dart';

class HistoryRepository {
  HistoryRepository(this._db);

  final db.AppDatabase _db;

  Future<List<History>> getByMangaId(int mangaId) async {
    final rows = await _db.getHistoryByMangaId(mangaId).get();
    return rows.map(HistoryMapper.fromRow).toList(growable: false);
  }

  /// Records or extends a read session for a chapter. Time spent reading is
  /// added on top of the existing duration via the SQLDelight-style ON
  /// CONFLICT clause we wrote into `history.drift`.
  Future<void> upsert({
    required int chapterId,
    required DateTime? readAt,
    required int timeReadMs,
  }) async {
    await _db.upsertHistory(
      chapterId,
      readAt?.millisecondsSinceEpoch,
      timeReadMs,
    );
  }

  Future<void> resetByMangaId(int mangaId) async {
    await _db.resetHistoryByMangaId(mangaId);
  }

  Future<void> removeAll() async {
    await _db.removeAllHistory();
  }

  Future<int> totalReadDurationMs() async {
    final result = await _db.getReadDuration().getSingle();
    return result;
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository(ref.watch(databaseProvider));
});
