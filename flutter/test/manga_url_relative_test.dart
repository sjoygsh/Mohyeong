import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/data/source/manga_url_migration.dart';
import 'package:mohyeong/data/source/source_url.dart';

/// Mihon stores a series' URL relative to its source's domain
/// (`setUrlWithoutDomain`), and `(source, url)` is the identity of a library
/// row. Mohyeong stored the absolute form, so a restored entry and the same
/// series opened from Browse were two different rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = 'https://aquareader.org';

  group('relativeMangaUrl', () {
    test('strips the source origin, Mihon style', () {
      expect(relativeMangaUrl('$base/manga/solo-leveling/', base),
          '/manga/solo-leveling/');
    });

    test('keeps query and fragment', () {
      expect(relativeMangaUrl('$base/manga/x/?tab=1#top', base),
          '/manga/x/?tab=1#top');
    });

    test('is idempotent — a relative url passes straight through', () {
      expect(relativeMangaUrl('/manga/x/', base), '/manga/x/');
    });

    test('decodes the path the way Kotlin URI.getPath does', () {
      // What Mihon put in the backup is the decoded form, so that is the
      // string a restored row has to be matched against.
      expect(relativeMangaUrl('$base/manga/a%20b/', base), '/manga/a b/');
    });

    test('escapes a raw space first, the way Mihon does', () {
      expect(relativeMangaUrl('$base/manga/a b/', base), '/manga/a b/');
    });

    test('ignores the host case and the scheme', () {
      expect(relativeMangaUrl('http://AquaReader.org/manga/x/', base),
          '/manga/x/');
    });

    test('leaves a link on another host absolute', () {
      // A sibling/CDN domain must stay whole — the extension would otherwise
      // re-attach its own base to a path that never existed there.
      const other = 'https://cdn.elsewhere.net/manga/x/';
      expect(relativeMangaUrl(other, base), other);
    });

    test('leaves junk alone rather than throwing', () {
      expect(relativeMangaUrl('', base), '');
      expect(relativeMangaUrl('$base/manga/x/', ''), '$base/manga/x/');
    });
  });

  group('normalizeMangaUrls', () {
    late AppDatabase db;
    const sourceId = 6247824327199706550;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    InstalledExtension ext() => const InstalledExtension(
          id: 'aqua',
          name: 'AquaReader',
          lang: 'en',
          baseUrl: base,
          versionCode: 1,
          supportsLatest: true,
          sourcePath: '/tmp/aqua/source.js',
          installUrl: null,
          declaredSourceId: sourceId,
        );

    Future<void> seed(String url) => db.customStatement(
          'INSERT INTO mangas (source, url, title, status, favorite, '
          'initialized, viewer, chapter_flags, cover_last_modified, '
          'date_added) VALUES (?, ?, ?, 0, 1, 1, 0, 0, 0, 0)',
          [sourceId, url, 'T $url'],
        );

    Future<List<String>> urls() async {
      final rows = await db
          .customSelect('SELECT url FROM mangas WHERE source = ? ORDER BY url',
              variables: [Variable.withInt(sourceId)])
          .get();
      return [for (final r in rows) r.data['url'] as String];
    }

    test('rewrites stored absolute urls onto the relative form', () async {
      await seed('$base/manga/one/');
      await seed('$base/manga/two/');

      final r = await normalizeMangaUrls(database: db, installed: [ext()]);

      expect(r.normalized, 2);
      expect(await urls(), ['/manga/one/', '/manga/two/']);
    });

    test('leaves the restored row alone when both rows exist', () async {
      await seed('/manga/one/');
      await seed('$base/manga/one/');

      final r = await normalizeMangaUrls(database: db, installed: [ext()]);

      expect(r.collisions, 1);
      expect(r.normalized, 0);
      expect(await urls(), ['/manga/one/', '$base/manga/one/']);
    });

    test('is idempotent — a second pass changes nothing', () async {
      await seed('$base/manga/one/');
      await normalizeMangaUrls(database: db, installed: [ext()]);
      final again = await normalizeMangaUrls(database: db, installed: [ext()]);
      expect(again.isEmpty, isTrue);
      expect(await urls(), ['/manga/one/']);
    });

    test('never touches another source\'s rows', () async {
      await db.customStatement(
        'INSERT INTO mangas (source, url, title, status, favorite, '
        'initialized, viewer, chapter_flags, cover_last_modified, '
        'date_added) VALUES (?, ?, ?, 0, 1, 1, 0, 0, 0, 0)',
        [42, '$base/manga/one/', 'other'],
      );
      final r = await normalizeMangaUrls(database: db, installed: [ext()]);
      expect(r.isEmpty, isTrue);
    });
  });
}
