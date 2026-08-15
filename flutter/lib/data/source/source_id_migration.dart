/// Remaps `mangas.source` from slug-derived ids onto the canonical Mihon
/// source ids that extensions now declare as `source_id`.
///
/// Mihon identifies a source by a folded MD5 of `"name.lowercase()/lang/
/// versionId"`, and that number is what a Mihon backup's manga rows carry.
/// Mohyeong keys extensions on disk by a readable slug (`asura`), and
/// [sourceNumericId] used to hash that slug — a value that could never equal
/// Mihon's, so every entry restored from a Mihon backup resolved to no
/// installed extension and became a stub ("Source not installed"), even with
/// the right extension sitting right there. Extensions now declare Mihon's
/// number; this moves rows written under the old scheme across to it.
///
/// Runs on every launch rather than behind a one-shot flag: an extension can
/// gain its declared id at any time (a later install/update), and after the
/// first pass the UPDATEs match nothing and cost one indexed lookup each.
///
/// Non-destructive by design. A row is only moved when the destination
/// `(source, url)` is free; if the same series is already there — the user
/// browsed to it in Mohyeong AND restored it from a Mihon backup — both rows
/// are left exactly as they are and counted in
/// [SourceIdRemapResult.collisions]. Merging them would mean choosing whose
/// read progress to discard, which is the user's call, not this migration's.
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart' as db;
import 'installed_extension.dart';
import 'source_id.dart';

class SourceIdRemapResult {
  const SourceIdRemapResult({
    required this.mangaRemapped,
    required this.collisions,
    required this.sourcesRemapped,
  });

  /// Manga rows moved onto a declared source id.
  final int mangaRemapped;

  /// Rows left behind because the destination `(source, url)` was taken.
  final int collisions;

  /// Rows moved in the `sources` display table.
  final int sourcesRemapped;

  bool get isEmpty =>
      mangaRemapped == 0 && collisions == 0 && sourcesRemapped == 0;
}

Future<SourceIdRemapResult> remapDeclaredSourceIds({
  required db.AppDatabase database,
  required List<InstalledExtension> installed,
}) async {
  var remapped = 0;
  var collisions = 0;
  var sourcesRemapped = 0;

  for (final ext in installed) {
    final declared = ext.declaredSourceId;
    if (declared == null) continue;
    final legacy = sourceNumericId(ext.id);
    if (legacy == declared) continue;

    // Rows that CAN'T move, counted before the update empties the old id.
    final blocked = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM mangas m '
          'WHERE m.source = ?1 AND EXISTS ('
          'SELECT 1 FROM mangas o WHERE o.source = ?2 AND o.url = m.url)',
          variables: [Variable.withInt(legacy), Variable.withInt(declared)],
        )
        .getSingle();
    collisions += blocked.data['c'] as int? ?? 0;

    remapped += await database.customUpdate(
      'UPDATE mangas SET source = ?2 WHERE source = ?1 AND NOT EXISTS ('
      'SELECT 1 FROM mangas o WHERE o.source = ?2 AND o.url = mangas.url)',
      variables: [Variable.withInt(legacy), Variable.withInt(declared)],
      updates: {database.mangas},
    );

    // The display row (id, lang, name). `_id` is the primary key, so a row
    // already sitting at the declared id wins and the legacy one is dropped
    // rather than colliding.
    final taken = await database
        .customSelect(
          'SELECT COUNT(*) AS c FROM sources WHERE _id = ?1',
          variables: [Variable.withInt(declared)],
        )
        .getSingle();
    if ((taken.data['c'] as int? ?? 0) > 0) {
      await database.customUpdate(
        'DELETE FROM sources WHERE _id = ?1',
        variables: [Variable.withInt(legacy)],
        updates: {database.sources},
      );
    } else {
      sourcesRemapped += await database.customUpdate(
        'UPDATE sources SET _id = ?2 WHERE _id = ?1',
        variables: [Variable.withInt(legacy), Variable.withInt(declared)],
        updates: {database.sources},
      );
    }
  }

  return SourceIdRemapResult(
    mangaRemapped: remapped,
    collisions: collisions,
    sourcesRemapped: sourcesRemapped,
  );
}
