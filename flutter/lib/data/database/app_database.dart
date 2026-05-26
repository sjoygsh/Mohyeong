import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// The Mohyeong app database.
///
/// Schema is defined across `tables/*.drift` files, which mirror the existing
/// SQLDelight `.sq` files from the Kotlin app at
/// `data/src/main/sqldelight/tachiyomi/data/`.
///
/// More tables will be added as the rewrite progresses. The full SQLDelight
/// schema includes: mangas, chapters, categories, mangas_categories, history,
/// manga_sync, sources, excluded_scanlators, scanlator_priority,
/// extension_repos, manga_links.
@DriftDatabase(
  include: {
    'tables/mangas.drift',
    'tables/chapters.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Bump this when adding/altering tables, and write a migration step in
  /// [MigrationStrategy.onUpgrade] below.
  ///
  /// Starts at 16 because the Kotlin app's last shipped migration is `15.sqm`.
  /// On first launch after the Flutter v1.0 upgrade, Drift will see the
  /// existing `mihon.db` at schemaVersion=15 and run any pending migrations.
  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          // No-op for now. Migrations from the Kotlin .sqm files will be
          // ported here when SQLite migration work begins.
        },
      );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'mihon',
  );
}
