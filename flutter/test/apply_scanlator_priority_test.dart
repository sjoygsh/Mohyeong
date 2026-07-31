import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/apply_scanlator_priority.dart';

/// When several scanlators publish the same chapter, the user can rank them
/// and see only their preferred release — port of the Kotlin fork's
/// `processedChapters`.
void main() {
  Chapter ch(int id, double number, {String? scanlator}) => Chapter(
        id: id,
        mangaId: 1,
        read: false,
        bookmark: false,
        lastPageRead: 0,
        dateFetch: 0,
        sourceOrder: id,
        url: '/c$id',
        name: 'Chapter $number',
        dateUpload: 0,
        chapterNumber: number,
        scanlator: scanlator,
        lastModifiedAt: 0,
        version: 1,
        volumeNumber: null,
      );

  test('no ranking leaves the list completely alone', () {
    final chapters = [ch(1, 1, scanlator: 'A'), ch(2, 1, scanlator: 'B')];
    final out = applyScanlatorPriority(chapters, const []);
    expect(identical(out, chapters), isTrue);
  });

  test('the highest-ranked scanlator wins the chapter number', () {
    final out = applyScanlatorPriority(
      [ch(1, 1, scanlator: 'Slow'), ch(2, 1, scanlator: 'Fast')],
      const ['Fast', 'Slow'],
    );
    expect(out.map((c) => c.id), [2]);
  });

  test('rank beats position — a later row still wins', () {
    final out = applyScanlatorPriority(
      [
        ch(1, 1, scanlator: 'C'),
        ch(2, 1, scanlator: 'B'),
        ch(3, 1, scanlator: 'A'),
      ],
      const ['A', 'B', 'C'],
    );
    expect(out.map((c) => c.id), [3]);
  });

  test('chapters nobody ranked are all kept', () {
    // Ranking one scanlator must not hide releases by scanlators the user
    // never expressed an opinion about.
    final out = applyScanlatorPriority(
      [ch(1, 1, scanlator: 'X'), ch(2, 1, scanlator: 'Y')],
      const ['Ranked'],
    );
    expect(out.map((c) => c.id), [1, 2]);
  });

  test('a ranked scanlator beats an unranked one on the same number', () {
    final out = applyScanlatorPriority(
      [ch(1, 1, scanlator: 'Unranked'), ch(2, 1, scanlator: 'Ranked')],
      const ['Ranked'],
    );
    expect(out.map((c) => c.id), [2]);
  });

  test('numbers with a single release are untouched', () {
    final out = applyScanlatorPriority(
      [ch(1, 2, scanlator: 'B'), ch(2, 1, scanlator: 'A')],
      const ['A', 'B'],
    );
    expect(out.map((c) => c.id), [1, 2]);
  });

  test('the incoming sort order is preserved', () {
    final out = applyScanlatorPriority(
      [
        ch(1, 3, scanlator: 'B'),
        ch(2, 2, scanlator: 'A'),
        ch(3, 2, scanlator: 'B'),
        ch(4, 1, scanlator: 'B'),
      ],
      const ['A', 'B'],
    );
    // 3 → 2 → 1 descending, with A winning number 2.
    expect(out.map((c) => c.chapterNumber), [3, 2, 1]);
    expect(out.map((c) => c.id), [1, 2, 4]);
  });

  test('unrecognised chapters ALL survive — the fork drops them', () {
    // Kotlin groups by chapter number without excluding unrecognised ones, so
    // every extra lands in one group keyed on the same sentinel and collapses
    // to a single row as soon as one of them is by a ranked scanlator. That
    // contradicts its own comment; we keep them.
    final out = applyScanlatorPriority(
      [
        ch(1, -1, scanlator: 'Ranked'),
        ch(2, -1, scanlator: 'Ranked'),
        ch(3, -1, scanlator: 'Other'),
      ],
      const ['Ranked'],
    );
    expect(out.map((c) => c.id), [1, 2, 3]);
  });

  test('a null scanlator never wins on rank but is not dropped alone', () {
    final out = applyScanlatorPriority(
      [ch(1, 1), ch(2, 1, scanlator: 'Ranked')],
      const ['Ranked'],
    );
    expect(out.map((c) => c.id), [2]);
    // On its own it survives, since nothing outranks it.
    final solo = applyScanlatorPriority([ch(1, 1)], const ['Ranked']);
    expect(solo.map((c) => c.id), [1]);
  });

  test('a duplicated name in the ranking keeps its best position', () {
    final out = applyScanlatorPriority(
      [ch(1, 1, scanlator: 'B'), ch(2, 1, scanlator: 'A')],
      const ['A', 'B', 'A'],
    );
    expect(out.map((c) => c.id), [2]);
  });
}
