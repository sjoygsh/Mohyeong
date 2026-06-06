import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/chapter/model/chapter.dart';
import 'package:mohyeong/domain/chapter/service/missing_chapters.dart';

/// Ports Mihon's `MissingChaptersTest` (domain) to confirm the gap maths
/// matches the Kotlin reference exactly.
Chapter _chapter(double number) =>
    Chapter.empty().copyWith(chapterNumber: number);

void main() {
  group('missingChaptersCount', () {
    test('returns 0 when empty list', () {
      expect(missingChaptersCount(const []), 0);
    });

    test('returns 0 when all unknown chapter numbers', () {
      expect(missingChaptersCount(const [-1.0, -1.0, -1.0]), 0);
    });

    test('handles repeated base chapter numbers', () {
      expect(missingChaptersCount(const [1.0, 1.0, 1.1, 1.5, 1.6, 1.99]), 0);
    });

    test('returns number of missing chapters', () {
      expect(
        missingChaptersCount(const [-1.0, 1.0, 2.0, 2.2, 4.0, 6.0, 10.0, 11.0]),
        5,
      );
    });
  });

  group('calculateChapterGap', () {
    test('returns difference', () {
      expect(calculateChapterGap(_chapter(10.0), _chapter(9.0)), 0);
      expect(calculateChapterGap(_chapter(10.0), _chapter(8.0)), 1);
      expect(calculateChapterGap(_chapter(10.0), _chapter(8.5)), 1);
      expect(calculateChapterGap(_chapter(10.0), _chapter(1.1)), 8);

      expect(calculateChapterGapNumbers(10.0, 9.0), 0);
      expect(calculateChapterGapNumbers(10.0, 8.0), 1);
      expect(calculateChapterGapNumbers(10.0, 8.5), 1);
      expect(calculateChapterGapNumbers(10.0, 1.1), 8);
    });

    test('returns 0 if either are not valid chapter numbers', () {
      expect(calculateChapterGap(_chapter(-1.0), _chapter(10.0)), 0);
      expect(calculateChapterGap(_chapter(99.0), _chapter(-1.0)), 0);

      expect(calculateChapterGapNumbers(-1.0, 10.0), 0);
      expect(calculateChapterGapNumbers(99.0, -1.0), 0);
    });

    test('returns 0 when either chapter is null', () {
      expect(calculateChapterGap(null, _chapter(10.0)), 0);
      expect(calculateChapterGap(_chapter(10.0), null), 0);
    });
  });
}
