/// Port of Mihon's `tachiyomi.domain.chapter.service.MissingChapters`.
/// Pure functions that compute how many chapters are missing across a list
/// or between two adjacent chapters, used to render the "Missing N chapters"
/// indicators in the manga details chapter list.
library;

import '../model/chapter.dart';

/// Number of chapters missing across [numbers] (the chapter numbers of a
/// series). Unknown numbers (-1) are ignored, fractional parts are dropped
/// (we can't tell whether 16.5 is missing), and duplicates are collapsed
/// before counting the integer gaps. 1:1 with Mihon's
/// `List<Double>.missingChaptersCount()`.
int missingChaptersCount(List<double> numbers) {
  if (numbers.isEmpty) return 0;

  final chapters = numbers
      .where((it) => it != -1.0)
      .map((it) => it.toInt())
      .toSet()
      .toList()
    ..sort();

  if (chapters.isEmpty) return 0;

  var count = 0;
  var previous = 0;
  for (final current in chapters) {
    if (current > previous + 1) {
      count += current - previous - 1;
    }
    previous = current;
  }
  return count;
}

/// Number of chapters missing between [higher] and [lower] (a chapter and the
/// next one along in reading order). Returns 0 when either chapter has an
/// unrecognised number. 1:1 with Mihon's `calculateChapterGap(Chapter?, Chapter?)`.
int calculateChapterGap(Chapter? higher, Chapter? lower) {
  if (higher == null || lower == null) return 0;
  if (!higher.isRecognizedNumber || !lower.isRecognizedNumber) return 0;
  return calculateChapterGapNumbers(higher.chapterNumber, lower.chapterNumber);
}

/// `floor(higher) - floor(lower) - 1`, or 0 when either number is negative.
/// 1:1 with Mihon's `calculateChapterGap(Double, Double)`.
int calculateChapterGapNumbers(double higherNumber, double lowerNumber) {
  if (higherNumber < 0.0 || lowerNumber < 0.0) return 0;
  return higherNumber.floor() - lowerNumber.floor() - 1;
}
