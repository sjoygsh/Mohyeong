import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// The Mohyeong app database.
///
/// Schema is defined across `tables/*.drift` files, which mirror the existing
/// SQLDelight `.sq` files from the Kotlin app at
/// `data/src/main/sqldelight/tachiyomi/data/`.
///
/// All 11 tables + 2 views from the Kotlin v0.19.x schema are mirrored here:
/// mangas, chapters, categories, mangas_categories, history, manga_sync,
/// sources, excluded_scanlators, scanlator_priority, extension_repos,
/// manga_links, libraryView, updatesView.
@DriftDatabase(
  include: {
    'tables/mangas.drift',
    'tables/chapters.drift',
    'tables/categories.drift',
    'tables/mangas_categories.drift',
    'tables/history.drift',
    'tables/manga_sync.drift',
    'tables/sources.drift',
    'tables/excluded_scanlators.drift',
    'tables/scanlator_priority.drift',
    'tables/extension_repos.drift',
    'tables/manga_links.drift',
    'tables/library_view.drift',
    'tables/updates_view.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// schemaVersion 16 is the first Flutter version.
  ///
  /// The Kotlin app shipped through SQLDelight migration 15.sqm, so existing
  /// installs land here at user_version=15 and get lifted to 16 by
  /// [_migrate15to16] below. Bump this number for any future schema change
  /// and add a corresponding step to [onUpgrade].
  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // Fresh install. Drift creates every table, index, trigger, view and
          // runs every @create statement declared in the .drift files.
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Migrate sequentially so a user on an older Drift schema (once we
          // start shipping post-1.0 changes) still gets every step applied.
          if (from < 16) {
            await _migrate15to16(m);
          }
          // Future: if (from < 17) await _migrate16to17(m);
        },
        beforeOpen: (details) async {
          // Drift respects PRAGMA foreign_keys per-connection, and the
          // SQLDelight setup had them on. Keep the same behaviour so the
          // ON DELETE CASCADE clauses on chapters/manga_sync/etc. actually
          // fire when a manga is deleted.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Transitions a DB that was last touched by the Kotlin app's `15.sqm`
  /// (user_version = 15) up to the Drift schemaVersion 16.
  ///
  /// The cumulative schema after Kotlin migrations 1..15 already matches what
  /// the .drift files declare for schemaVersion 16, so structurally there is
  /// nothing to add. However, the two views (`libraryView`, `updatesView`)
  /// were re-defined across migrations 6, 7, and 9 -- we drop and recreate
  /// them so they unambiguously match the definitions Drift will use for
  /// generated query code, regardless of any drift from the user's last
  /// installed version.
  Future<void> _migrate15to16(Migrator m) async {
    await customStatement('DROP VIEW IF EXISTS libraryView');
    await customStatement('DROP VIEW IF EXISTS updatesView');
    await m.createView(libraryView);
    await m.createView(updatesView);
  }
}

QueryExecutor _openConnection() {
  // `name: 'mihon'` resolves to the same on-disk path the Kotlin app used
  // (`/data/data/app.mohyeong/databases/mihon.db` on Android). Since the
  // applicationId is unchanged across the v0.19 -> v1.0 in-place update,
  // existing user data is preserved.
  return driftDatabase(
    name: 'mihon',
  );
}
