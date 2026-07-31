import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/util/stream_combine.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/merge_linked_chapters.dart';

/// Linked sources put the same series on several mirrors. The merged list has
/// to show each chapter once, resolve every row back to the manga it actually
/// belongs to, and keep read state shared — port of the Kotlin fork's
/// `mergeChapters`.
void main() {
  Chapter ch(
    int id,
    int mangaId,
    double number, {
    bool read = false,
    int sourceOrder = 0,
    String? name,
    String? scanlator,
  }) =>
      Chapter(
        id: id,
        mangaId: mangaId,
        read: read,
        bookmark: false,
        lastPageRead: 0,
        dateFetch: 0,
        sourceOrder: sourceOrder,
        url: '/c$id',
        name: name ?? 'Chapter $number',
        dateUpload: 0,
        chapterNumber: number,
        scanlator: scanlator,
        lastModifiedAt: 0,
        version: 1,
        volumeNumber: null,
      );

  group('mergeLinkedChapters', () {
    test('nothing linked returns the primary list untouched', () {
      final primary = [ch(1, 1, 3, sourceOrder: 9), ch(2, 1, 1)];
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: primary,
        linked: const [],
      );
      // Same instances, same order — the feature is additive, and a manga
      // with no cluster must not have its source ordering rewritten.
      expect(identical(merged.chapters, primary), isTrue);
      expect(merged.chapters.first.sourceOrder, 9);
    });

    test('a chapter on two sources appears once, and the primary wins', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1), ch(2, 1, 2)],
        linked: [
          [ch(10, 2, 1), ch(11, 2, 2)],
        ],
      );
      expect(merged.chapters.map((c) => c.id), [2, 1]);
      expect(merged.chapters.every((c) => c.mangaId == 1), isTrue);
    });

    test('a chapter only the mirror has is pulled in', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1)],
        linked: [
          [ch(10, 2, 1), ch(11, 2, 2)],
        ],
      );
      // 2 comes from the mirror and leads, being the higher number.
      expect(merged.chapters.map((c) => c.id), [11, 1]);
      expect(merged.chapters.first.mangaId, 2);
    });

    test('among mirrors the earlier one in cluster order wins', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: const [],
        linked: [
          [ch(10, 2, 5)],
          [ch(20, 3, 5)],
        ],
      );
      expect(merged.chapters.single.mangaId, 2);
    });

    test('sourceOrder is resequenced so the existing sort still works', () {
      // Every source numbers from 0 independently; a naive sort by the stored
      // sourceOrder would interleave them nonsensically.
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1, sourceOrder: 0)],
        linked: [
          [ch(10, 2, 3, sourceOrder: 0), ch(11, 2, 2, sourceOrder: 1)],
        ],
      );
      expect(merged.chapters.map((c) => c.chapterNumber), [3, 2, 1]);
      expect(merged.chapters.map((c) => c.sourceOrder), [0, 1, 2]);
    });

    test('unrecognised numbers all survive, after the numbered ones', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, -1, name: 'Extra'), ch(2, 1, 1)],
        linked: [
          [ch(10, 2, -1, name: 'Omake')],
        ],
      );
      // Nothing to dedupe them on, so both extras stay.
      expect(merged.chapters.map((c) => c.id), [2, 1, 10]);
      expect(merged.chapters.map((c) => c.sourceOrder), [0, 1, 2]);
    });

    test('an excluded winner does not take the chapter down with it', () {
      // The bug this guards: dedupe first, filter second. The mirror's copy
      // won chapter 5, the render-time filter then dropped it, and the
      // allowed copy on the second mirror had already lost — so chapter 5
      // vanished from the list entirely.
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: const [],
        linked: [
          [ch(10, 2, 5, scanlator: 'Bad')],
          [ch(20, 3, 5, scanlator: 'Good')],
        ],
        excludedScanlators: const {'Bad'},
      );
      expect(merged.chapters.single.id, 20);
      // The loser is gone from the index too, so marking read can't reach it.
      expect(merged.byNumber[5]!.map((c) => c.id), [20]);
    });

    test('a chapter every source excludes is dropped', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1)],
        linked: [
          [ch(10, 2, 5, scanlator: 'Bad')],
        ],
        excludedScanlators: const {'Bad'},
      );
      expect(merged.chapters.map((c) => c.id), [1]);
    });

    test('excluding a scanlator keeps it listed, or it cannot be undone', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1, scanlator: 'Good')],
        linked: [
          [ch(10, 2, 2, scanlator: 'Bad')],
        ],
        excludedScanlators: const {'Bad'},
      );
      expect(merged.availableScanlators, {'Good', 'Bad'});
    });

    test('unrecognised chapters honour the exclusion too', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, -1, scanlator: 'Bad')],
        linked: [
          [ch(10, 2, 1)],
        ],
        excludedScanlators: const {'Bad'},
      );
      expect(merged.chapters.map((c) => c.id), [10]);
    });

    test('byNumber indexes every copy so read state can be shared', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1)],
        linked: [
          [ch(10, 2, 1)],
          [ch(20, 3, 1)],
        ],
      );
      expect(merged.byNumber[1]!.map((c) => c.id), [1, 10, 20]);
    });
  });

  group('expandAcrossCluster', () {
    test('marking one row hits every copy of that chapter', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1)],
        linked: [
          [ch(10, 2, 1)],
        ],
      );
      final expanded =
          expandAcrossCluster([merged.chapters.single], merged.byNumber);
      expect(expanded.map((c) => c.id), [1, 10]);
    });

    test('an unrecognised chapter expands to just itself', () {
      final odd = ch(7, 1, -1);
      expect(expandAcrossCluster([odd], const {}).map((c) => c.id), [7]);
    });

    test('overlapping selections never double up', () {
      final merged = mergeLinkedChapters(
        primaryMangaId: 1,
        primaryChapters: [ch(1, 1, 1), ch(2, 1, 2)],
        linked: [
          [ch(10, 2, 1), ch(11, 2, 2)],
        ],
      );
      final expanded =
          expandAcrossCluster(merged.chapters, merged.byNumber);
      expect(expanded.map((c) => c.id).toSet(), {1, 2, 10, 11});
      expect(expanded.length, 4);
    });
  });

  group('stream combinators', () {
    test('combineLatestList waits for every stream then tracks latest',
        () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final seen = <List<int>>[];
      final sub = combineLatestList([a.stream, b.stream]).listen(seen.add);

      a.add(1);
      await pumpEventQueue();
      expect(seen, isEmpty, reason: 'b has not produced yet');

      b.add(2);
      await pumpEventQueue();
      expect(seen.last, [1, 2]);

      a.add(3);
      await pumpEventQueue();
      expect(seen.last, [3, 2]);

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('combineLatestList with no streams emits once', () async {
      expect(await combineLatestList<int>(const []).first, isEmpty);
    });

    test('switchMap survives two outer events in the same turn', () async {
      // Regression guard for back-to-back outer events: whatever the delivery
      // timing, exactly one inner subscription may survive and it must be the
      // latest. Both the awaiting and the synchronous implementation pass
      // today; this pins the property so a future rewrite can't lose it.
      final outer = StreamController<int>();
      final inners = {
        1: StreamController<String>.broadcast(),
        2: StreamController<String>.broadcast(),
      };
      final seen = <String>[];
      final sub =
          switchMap(outer.stream, (int i) => inners[i]!.stream).listen(seen.add);

      outer.add(1);
      outer.add(2);
      await pumpEventQueue();

      inners[1]!.add('leaked');
      inners[2]!.add('live');
      await pumpEventQueue();

      expect(seen, ['live'], reason: 'the first inner must be cancelled');
      expect(inners[1]!.hasListener, isFalse);

      await sub.cancel();
      await outer.close();
      for (final c in inners.values) {
        await c.close();
      }
    });

    test('combineLatest2 waits for both, then tracks the latest of each',
        () async {
      final a = StreamController<int>();
      final b = StreamController<String>();
      final seen = <String>[];
      final sub = combineLatest2(a.stream, b.stream, (int x, String y) => '$x$y')
          .listen(seen.add);

      a.add(1);
      await pumpEventQueue();
      expect(seen, isEmpty);

      b.add('a');
      await pumpEventQueue();
      expect(seen, ['1a']);

      b.add('b');
      await pumpEventQueue();
      expect(seen.last, '1b');

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('switchMap drops the previous inner stream', () async {
      final outer = StreamController<int>();
      final inners = <int, StreamController<String>>{
        1: StreamController<String>(),
        2: StreamController<String>(),
      };
      final seen = <String>[];
      final sub =
          switchMap(outer.stream, (int i) => inners[i]!.stream).listen(seen.add);

      outer.add(1);
      await pumpEventQueue();
      inners[1]!.add('a');
      await pumpEventQueue();
      expect(seen, ['a']);

      outer.add(2);
      await pumpEventQueue();
      // The first inner is now cancelled — its emissions must not surface.
      inners[1]!.add('stale');
      inners[2]!.add('b');
      await pumpEventQueue();
      expect(seen, ['a', 'b']);

      await sub.cancel();
      await outer.close();
      for (final c in inners.values) {
        await c.close();
      }
    });
  });
}
