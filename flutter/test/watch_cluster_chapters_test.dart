import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/watch_cluster_chapters.dart';
import 'package:mohyeong/domain/manga/model/manga.dart';
import 'package:mohyeong/domain/manga/model/update_strategy.dart';

/// The composition behind the details screen's chapter list. Everything here
/// used to be inline in the widget, so the only way to exercise it was to run
/// the app — which is exactly how the "a merged chapter can vanish" bug
/// survived review.
void main() {
  Chapter ch(int id, int mangaId, double number, {String? scanlator}) => Chapter(
        id: id,
        mangaId: mangaId,
        read: false,
        bookmark: false,
        lastPageRead: 0,
        dateFetch: 0,
        sourceOrder: 0,
        url: '/c$id',
        name: 'Chapter $number',
        dateUpload: 0,
        chapterNumber: number,
        scanlator: scanlator,
        lastModifiedAt: 0,
        version: 1,
        volumeNumber: null,
      );

  Manga manga(int id) => Manga(
        id: id,
        source: 1,
        favorite: true,
        lastUpdate: 0,
        nextUpdate: 0,
        fetchInterval: 0,
        dateAdded: 0,
        viewerFlags: 0,
        chapterFlags: 0,
        coverLastModified: 0,
        url: '/m$id',
        title: 'Manga $id',
        artist: null,
        author: null,
        description: null,
        genre: null,
        status: 0,
        thumbnailUrl: null,
        updateStrategy: UpdateStrategy.alwaysUpdate,
        initialized: true,
        lastModifiedAt: 0,
        favoriteModifiedAt: null,
        version: 0,
        notes: '',
      );

  late StreamController<List<Manga>> links;
  late Map<int, StreamController<List<Chapter>>> chapters;
  late StreamController<Set<String>> excluded;

  setUp(() {
    links = StreamController<List<Manga>>.broadcast();
    chapters = {};
    excluded = StreamController<Set<String>>.broadcast();
  });

  tearDown(() async {
    await links.close();
    await excluded.close();
    for (final c in chapters.values) {
      await c.close();
    }
  });

  StreamController<List<Chapter>> chapterCtl(int mangaId) =>
      chapters[mangaId] ??= StreamController<List<Chapter>>.broadcast();

  Stream<ClusterChapters> subject(int primaryId) => watchClusterChapters(
        primaryMangaId: primaryId,
        watchLinked: (_) => links.stream,
        watchChapters: (id) => chapterCtl(id).stream,
        watchExcludedScanlators: (_) => excluded.stream,
      );

  test('with nothing linked it is the plain per-manga list', () async {
    final seen = <ClusterChapters>[];
    final sub = subject(1).listen(seen.add);

    links.add(const []);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 2), ch(2, 1, 1)]);
    await pumpEventQueue();

    expect(seen.single.merged.chapters.map((c) => c.id), [1, 2]);
    expect(seen.single.mangaById, isEmpty);
    // No index either — there is nothing to share read state with.
    expect(seen.single.merged.byNumber, isEmpty);
    await sub.cancel();
  });

  test('linking a source re-merges without re-mounting anything', () async {
    final seen = <ClusterChapters>[];
    final sub = subject(1).listen(seen.add);

    links.add(const []);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 1)]);
    await pumpEventQueue();
    expect(seen.last.merged.chapters.length, 1);

    // The cluster gains a mirror that has a chapter the primary lacks.
    links.add([manga(2)]);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 1)]);
    chapterCtl(2).add([ch(10, 2, 1), ch(11, 2, 2)]);
    excluded.add(const {});
    await pumpEventQueue();

    expect(seen.last.merged.chapters.map((c) => c.id), [11, 1]);
    expect(seen.last.mangaById.keys, [2]);
    await sub.cancel();
  });

  test('excluding a scanlator re-merges and cannot lose the chapter',
      () async {
    // The regression this file exists for: the excluded copy wins the number
    // and then gets filtered, taking the chapter with it.
    final seen = <ClusterChapters>[];
    final sub = subject(1).listen(seen.add);

    links.add([manga(2), manga(3)]);
    await pumpEventQueue();
    chapterCtl(1).add(const []);
    chapterCtl(2).add([ch(10, 2, 5, scanlator: 'Bad')]);
    chapterCtl(3).add([ch(20, 3, 5, scanlator: 'Good')]);
    excluded.add(const {});
    await pumpEventQueue();
    expect(seen.last.merged.chapters.single.id, 10,
        reason: 'nothing excluded yet, first mirror wins');

    excluded.add(const {'Bad'});
    await pumpEventQueue();
    expect(seen.last.merged.chapters.single.id, 20,
        reason: 'the allowed copy must take the number, not disappear');
    await sub.cancel();
  });

  test('unlinking the last mirror goes back to the plain list', () async {
    final seen = <ClusterChapters>[];
    final sub = subject(1).listen(seen.add);

    links.add([manga(2)]);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 1)]);
    chapterCtl(2).add([ch(10, 2, 2)]);
    excluded.add(const {});
    await pumpEventQueue();
    expect(seen.last.merged.chapters.length, 2);

    links.add(const []);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 1)]);
    await pumpEventQueue();

    expect(seen.last.merged.chapters.map((c) => c.id), [1]);
    expect(seen.last.mangaById, isEmpty);
    await sub.cancel();
  });

  test('a mirror emitting again refreshes the merged list', () async {
    final seen = <ClusterChapters>[];
    final sub = subject(1).listen(seen.add);

    links.add([manga(2)]);
    await pumpEventQueue();
    chapterCtl(1).add([ch(1, 1, 1)]);
    chapterCtl(2).add([ch(10, 2, 1)]);
    excluded.add(const {});
    await pumpEventQueue();
    final before = seen.length;

    // The mirror gains a chapter — a source refresh, not a cluster change.
    chapterCtl(2).add([ch(10, 2, 1), ch(11, 2, 3)]);
    await pumpEventQueue();

    expect(seen.length, greaterThan(before));
    expect(seen.last.merged.chapters.map((c) => c.chapterNumber), [3, 1]);
    // Both copies of 1 stay indexed so read state still spans the cluster.
    expect(seen.last.merged.byNumber[1]!.map((c) => c.id), [1, 10]);
    await sub.cancel();
  });
}
