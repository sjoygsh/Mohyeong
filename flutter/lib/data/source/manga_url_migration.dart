/// Rewrites `mangas.url` from the absolute form Mohyeong used to store onto
/// the domain-relative form Mihon stores (and that the app now writes).
///
/// See [relativeMangaUrl] for why the absolute form was wrong: `(source, url)`
/// is a series' identity, so a library restored from a Mihon backup and the
/// same series opened from Browse were two unrelated rows.
///
/// Runs on every launch next to [remapDeclaredSourceIds], for the same reason
/// — an extension can arrive or change its declared id at any time — and after
/// the first pass it selects a handful of rows and updates none.
///
/// Non-destructive by the same rule: a row moves only when the destination
/// `(source, url)` is free. If both rows exist, merging them would mean
/// picking whose read progress to throw away, which is the user's call.
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart' as db;
import 'installed_extension.dart';
import 'source_url.dart';

class MangaUrlNormalizeResult {
  const MangaUrlNormalizeResult({
    required this.normalized,
    required this.collisions,
  });

  /// Rows rewritten to the domain-relative URL.
  final int normalized;

  /// Rows left absolute because the relative URL was already taken.
  final int collisions;

  bool get isEmpty => normalized == 0 && collisions == 0;
}

Future<MangaUrlNormalizeResult> normalizeMangaUrls({
  required db.AppDatabase database,
  required List<InstalledExtension> installed,
}) async {
  var normalized = 0;
  var collisions = 0;

  for (final ext in installed) {
    if (ext.baseUrl.isEmpty) continue;
    final rows = await database
        .customSelect(
          "SELECT _id, url FROM mangas WHERE source = ?1 AND url LIKE 'http%'",
          variables: [Variable.withInt(ext.sourceId)],
        )
        .get();

    for (final row in rows) {
      final id = row.data['_id'] as int;
      final url = row.data['url'] as String;
      final relative = relativeMangaUrl(url, ext.baseUrl);
      if (relative == url) continue;

      final taken = await database
          .customSelect(
            'SELECT COUNT(*) AS c FROM mangas WHERE source = ?1 AND url = ?2',
            variables: [
              Variable.withInt(ext.sourceId),
              Variable.withString(relative),
            ],
          )
          .getSingle();
      if ((taken.data['c'] as int? ?? 0) > 0) {
        collisions++;
        continue;
      }

      normalized += await database.customUpdate(
        'UPDATE mangas SET url = ?2 WHERE _id = ?1',
        variables: [Variable.withInt(id), Variable.withString(relative)],
        updates: {database.mangas},
      );
    }
  }

  return MangaUrlNormalizeResult(
    normalized: normalized,
    collisions: collisions,
  );
}
