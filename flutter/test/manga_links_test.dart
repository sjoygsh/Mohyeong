import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/database/app_database.dart';
import 'package:mohyeong/data/manga/manga_links_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clusters are anchored at the primary, so promoting a linked title is not
/// an edge flip — every row touching the old primary has to be dropped and
/// re-anchored the other way round. Port of Kotlin's `MakeLinkedPrimary`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MangaLinksRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MangaLinksRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedManga(int id) => db.customInsert(
        'INSERT INTO mangas(_id,source,url,title,status,favorite,initialized,'
        'viewer,chapter_flags,cover_last_modified,date_added) '
        'VALUES(?,1,?,?,0,1,0,0,0,0,0)',
        variables: [Variable(id), Variable('/m$id'), Variable('M$id')],
      );

  /// 1 is the primary; 2, 3 and 4 hang off it in that order.
  Future<void> seedCluster() async {
    for (final id in [1, 2, 3, 4]) {
      await seedManga(id);
    }
    await repo.link(1, 2, priority: 0);
    await repo.link(1, 3, priority: 1);
    await repo.link(1, 4, priority: 2);
  }

  test('promoting a linked title re-anchors the whole cluster', () async {
    await seedCluster();

    expect(await repo.makePrimary(1, 3), isTrue);

    // The old primary is now just another linked entry, and it leads —
    // Kotlin gives the demoted primary priority 0.
    final linked = await repo.getLinked(3);
    expect(linked.map((m) => m.id), [1, 2, 4]);

    // Nothing hangs off the old primary any more.
    expect(await repo.getLinked(1), isEmpty);

    // ...and the cluster is reachable backwards from every member.
    expect((await repo.getPrimariesOf(1)).map((m) => m.id), [3]);
    expect((await repo.getPrimariesOf(2)).map((m) => m.id), [3]);
  });

  test('siblings keep their relative order behind the demoted primary',
      () async {
    await seedCluster();
    await repo.makePrimary(1, 2);

    // 3 preceded 4 under the old primary and still does under the new one.
    expect((await repo.getLinked(2)).map((m) => m.id), [1, 3, 4]);
  });

  test('a two-title cluster simply swaps ends', () async {
    await seedManga(1);
    await seedManga(2);
    await repo.link(1, 2);

    expect(await repo.makePrimary(1, 2), isTrue);
    expect((await repo.getLinked(2)).map((m) => m.id), [1]);
    expect(await repo.getLinked(1), isEmpty);
  });

  test('promoting is a no-op unless the target is in the cluster', () async {
    await seedCluster();
    await seedManga(9);

    expect(await repo.makePrimary(1, 9), isFalse);
    expect(await repo.makePrimary(1, 1), isFalse);
    // The cluster is untouched by either refusal.
    expect((await repo.getLinked(1)).map((m) => m.id), [2, 3, 4]);
  });

  test('a promotion round trip returns the cluster to where it started',
      () async {
    await seedCluster();

    await repo.makePrimary(1, 2);
    await repo.makePrimary(2, 1);

    expect((await repo.getLinked(1)).map((m) => m.id), [2, 3, 4]);
    expect(await repo.getLinked(2), isEmpty);
  });
}
