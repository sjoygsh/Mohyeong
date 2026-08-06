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

  /// Tracks for many manga at once, grouped by manga id — the bulk form of
  /// [getByMangaId] for whole-library walks (backup creation).
  Future<Map<int, List<Track>>> getByMangaIds(Iterable<int> mangaIds) async {
    final ids = mangaIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.mangaSync)
          ..where((t) => t.mangaId.isIn(ids)))
        .get();
    final out = <int, List<Track>>{};
    for (final r in rows) {
      (out[r.mangaId] ??= <Track>[]).add(TrackMapper.fromRow(r));
    }
    return out;
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

  /// Insert-or-replace a track row. The `manga_sync` table's UNIQUE(manga_id,
  /// sync_id) ON CONFLICT REPLACE constraint means upserting a track for a
  /// (manga, tracker) pair that already exists overwrites the prior row.
  Future<int> upsert(Track track) async {
    return _db
        .into(_db.mangaSync)
        .insertOnConflictUpdate(TrackMapper.toCompanion(track));
  }
}

final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  return TrackRepository(ref.watch(databaseProvider));
});
