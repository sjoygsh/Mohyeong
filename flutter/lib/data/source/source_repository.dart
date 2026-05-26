import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/source/model/source.dart';
import '../database/app_database.dart' as db;
import '../database/database_provider.dart';
import 'source_mapper.dart';

/// Persistence layer for the `sources` table -- the small (id, lang, name)
/// row Mihon writes whenever a source surfaces a manga so the UI can render
/// it later even if the extension that produced it is uninstalled.
class SourceRepository {
  SourceRepository(this._db);

  final db.AppDatabase _db;

  Future<List<Source>> getAll() async {
    final rows = await _db.findAllSources().get();
    return rows.map(SourceMapper.fromRow).toList(growable: false);
  }

  Future<Source?> findById(int id) async {
    final row = await _db.findSourceById(id).getSingleOrNull();
    return row == null ? null : SourceMapper.fromRow(row);
  }

  Future<void> upsert({
    required int id,
    required String lang,
    required String name,
  }) async {
    await _db.upsertSource(id, lang, name);
  }
}

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepository(ref.watch(databaseProvider));
});
