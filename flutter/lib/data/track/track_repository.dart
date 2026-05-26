import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/track/model/track.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'track_mapper.dart';

class TrackRepository {
  TrackRepository(this._db);

  final db.AppDatabase _db;

  Future<List<Track>> getAll() async {
    final rows = await _db.getTracks().get();
    return rows.map(TrackMapper.fromRow).toList(growable: false);
  }

  Future<List<Track>> getByMangaId(int mangaId) async {
    final rows = await _db.getTracksByMangaId(mangaId).get();
    return rows.map(TrackMapper.fromRow).toList(growable: false);
  }

  Stream<List<Track>> watchByMangaId(int mangaId) {
    return _db.getTracksByMangaId(mangaId).watch().map(
          (rows) => rows.map(TrackMapper.fromRow).toList(growable: false),
        );
  }

  Future<Track?> getById(int id) async {
    final row = await _db.getTrackById(id).getSingleOrNull();
    return row == null ? null : TrackMapper.fromRow(row);
  }

  Future<void> delete({required int mangaId, required int trackerId}) async {
    await _db.deleteMangaSync(mangaId, trackerId);
  }
}

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return TrackRepository(ref.watch(databaseProvider));
});
