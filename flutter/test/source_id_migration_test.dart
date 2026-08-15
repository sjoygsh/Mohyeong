import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/data/source/source_id.dart';
import 'package:mohyeong/data/source/source_id_migration.dart';

/// A Mihon backup's manga rows carry Mihon's own 64-bit source id (a folded
/// MD5 of `name/lang/versionId`). Our extensions are keyed on disk by a slug,
/// whose hash can never equal that number — so every restored entry resolved
/// to no installed extension and read as "Source not installed". Extensions
/// now declare Mihon's id; these cover the declaration and the remap of rows
/// written under the old scheme.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InstalledExtension ext(String id, {int? sourceId}) => InstalledExtension(
        id: id,
        name: 'Asura Scans',
        lang: 'en',
        baseUrl: 'https://asuracomic.net',
        versionCode: 1,
        supportsLatest: true,
        sourcePath: '/tmp/$id/source.js',
        installUrl: null,
        declaredSourceId: sourceId,
      );

  group('InstalledExtension.sourceId', () {
    test('a declared source_id is the extension identity', () {
      expect(ext('asura', sourceId: 6247824327199706550).sourceId,
          6247824327199706550);
    });

    test('without one it stays the slug hash it always was', () {
      expect(ext('asura').sourceId, sourceNumericId('asura'));
    });

    test('reads source_id off a manifest as a decimal string', () {
      final e = InstalledExtension.fromManifest(const {
        'id': 'asura',
        'name': 'Asura Scans',
        'lang': 'en',
        // Written as a string: the value exceeds what a JS number holds
        // exactly, so an extension that emitted it as a number would round.
        'source_id': '6247824327199706550',
      }, '/tmp/asura/source.js');
      expect(e.sourceId, 6247824327199706550);
    });

    test('a manifest without source_id falls back, not crashes', () {
      final e = InstalledExtension.fromManifest(
        const {'id': 'asura', 'name': 'Asura Scans'},
        '/tmp/asura/source.js',
      );
      expect(e.sourceId, sourceNumericId('asura'));
    });
  });

  group('remapDeclaredSourceIds', () {
    late AppDatabase db;
    final legacy = sourceNumericId('asura');
    const mihon = 6247824327199706550;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> seed(int source, String url) => db.customStatement(
          'INSERT INTO mangas (source, url, title, status, favorite, '
          'initialized, viewer, chapter_flags, cover_last_modified, '
          'date_added) VALUES (?, ?, ?, 0, 1, 1, 0, 0, 0, 0)',
          [source, url, 'T $url'],
        );

    Future<int> countAt(int source) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM mangas WHERE source = ?',
              variables: [Variable.withInt(source)])
          .getSingle();
      return row.data['c'] as int;
    }

    test('moves rows off the slug hash onto the declared id', () async {
      await seed(legacy, 'm/1');
      await seed(legacy, 'm/2');

      final r = await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );

      expect(r.mangaRemapped, 2);
      expect(await countAt(legacy), 0);
      expect(await countAt(mihon), 2);
    });

    test('leaves rows alone when the extension declares nothing', () async {
      await seed(legacy, 'm/1');
      final r = await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura')],
      );
      expect(r.isEmpty, isTrue);
      expect(await countAt(legacy), 1);
    });

    test('does not clobber a restored row that already holds the url',
        () async {
      // The same series both browsed-to locally and restored from a backup.
      // Merging would mean discarding one side's read progress, so both stay.
      await seed(legacy, 'm/1');
      await seed(mihon, 'm/1');
      await seed(legacy, 'm/2');

      final r = await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );

      expect(r.collisions, 1);
      expect(r.mangaRemapped, 1, reason: 'only the free url moves');
      expect(await countAt(legacy), 1);
      expect(await countAt(mihon), 2);
    });

    test('is idempotent — a second pass is a no-op', () async {
      await seed(legacy, 'm/1');
      await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );
      final again = await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );
      expect(again.isEmpty, isTrue);
      expect(await countAt(mihon), 1);
    });

    test('carries the sources display row across too', () async {
      await db.upsertSource(legacy, 'en', 'Asura Scans');
      final r = await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );
      expect(r.sourcesRemapped, 1);
      final row = await db.findSourceById(mihon).getSingleOrNull();
      expect(row, isNotNull);
      expect(await db.findSourceById(legacy).getSingleOrNull(), isNull);
    });

    test('drops the legacy display row when the declared id already has one',
        () async {
      await db.upsertSource(legacy, 'en', 'Asura Scans');
      await db.upsertSource(mihon, 'en', 'Asura Scans');
      await remapDeclaredSourceIds(
        database: db,
        installed: [ext('asura', sourceId: mihon)],
      );
      expect(await db.findSourceById(legacy).getSingleOrNull(), isNull);
      expect(await db.findSourceById(mihon).getSingleOrNull(), isNotNull);
    });
  });
}
