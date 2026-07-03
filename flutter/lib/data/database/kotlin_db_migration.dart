import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One-time migration of the SQLDelight database written by the Kotlin
/// v0.19.x app (`tachiyomi.db`) into the location Drift expects
/// (`mihon.sqlite` inside `getApplicationDocumentsDirectory()`).
///
/// The `applicationId` stays `app.mohyeong` across the v0.19 -> v1.0
/// in-place update, so the legacy file is readable from the same data
/// sandbox. Once the file is copied, Drift's [MigrationStrategy.onUpgrade]
/// takes the DB the rest of the way (user_version 15 -> 16).
///
/// This is an Android-only path -- the Kotlin app never shipped on iOS,
/// desktop, or web, so other platforms have nothing to migrate.
class KotlinDbMigration {
  KotlinDbMigration._();

  /// Resolves the on-disk path Drift should open, performing the legacy
  /// copy if (and only if) it is the first launch after upgrading from
  /// the Kotlin build.
  ///
  /// Always returns the Drift target path; the copy is a side effect.
  static Future<String> resolveDatabasePath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final driftPath = p.join(docsDir.path, 'mihon.sqlite');

    if (!Platform.isAndroid) {
      return driftPath;
    }

    final driftFile = File(driftPath);
    if (await driftFile.exists()) {
      // Drift DB already present -- either a fresh Flutter install that
      // has run before, or a previous successful migration. Nothing to do.
      return driftPath;
    }

    // On Android, getApplicationDocumentsDirectory() resolves to
    // `/data/data/<pkg>/app_flutter/`. The SQLDelight DB lives at
    // `/data/data/<pkg>/databases/tachiyomi.db`, i.e. one directory up
    // and into `databases/`.
    final legacyDir = Directory(p.join(p.dirname(docsDir.path), 'databases'));
    final legacyFile = File(p.join(legacyDir.path, 'tachiyomi.db'));
    if (!await legacyFile.exists()) {
      return driftPath;
    }

    // Make sure the destination directory exists. getApplicationDocuments
    // is normally created by Flutter on first call, but be defensive in
    // case the user wiped app_flutter manually.
    await driftFile.parent.create(recursive: true);

    // Copy the WAL/SHM sidecars FIRST and land the main file last via a
    // staging name + rename: `mihon.sqlite` existing is the "migration
    // done" marker above, so it must only appear once everything it depends
    // on is in place. (Main-first left a window where a crash before the
    // WAL copy made the next launch skip migration and silently drop the
    // Kotlin app's most recent committed transactions.) A crash mid-copy
    // now simply re-runs the whole migration on the next launch.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${legacyFile.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.copy('$driftPath$suffix');
      }
    }
    final staging = await legacyFile.copy('$driftPath.migrating');
    await staging.rename(driftPath);

    return driftPath;
  }
}
