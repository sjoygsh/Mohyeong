import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/domain/chapter/service/chapter_recognition.dart';

/// Cases taken from Kotlin `ChapterRecognitionTest` and from the worked
/// examples in `ChapterRecognition.kt`'s own comments.
void main() {
  double parse(String title, String name, [double? supplied]) =>
      parseChapterNumber(title, name, chapterNumber: supplied);

  group('a number the source supplied wins', () {
    test('anything above -1 is trusted as given', () {
      expect(parse('Title', 'Chapter 5', 12.0), 12.0);
      expect(parse('Title', 'Chapter 5', 0.0), 0.0);
    });

    test('-2 is the deliberately-unnumbered sentinel and survives', () {
      expect(parse('Title', 'Chapter 5', -2.0), -2.0);
    });

    test('-1 means "nothing supplied" — the name is read instead', () {
      // This is the case that matters: both shared theme factories emit -1.
      expect(parse('Title', 'Chapter 5', -1.0), 5.0);
      expect(parse('Title', 'Chapter 5'), 5.0);
    });
  });

  group('the fork\'s worked examples', () {
    test('Ch. prefix', () {
      expect(
        parse('Mokushiroku Alice', 'Mokushiroku Alice Vol.1 Ch. 4: '
            'Misrepresentation'),
        4.0,
      );
    });

    test('a bare number after the title', () {
      expect(parse('Bleach', 'Bleach 567: Down With Snowwhite'), 567.0);
    });

    test('volume and version tags are not the chapter', () {
      expect(
        parse('Prison School', 'Prison School 12 v.1 vol004 version1243 '
            'volume64'),
        12.0,
      );
    });
  });

  group('decimals and suffixes', () {
    test('a decimal chapter', () {
      expect(parse('Title', 'Chapter 5.5'), 5.5);
    });

    test('extra / omake / special get their reserved fractions', () {
      expect(parse('Title', 'Chapter 8 extra'), 8.99);
      expect(parse('Title', 'Chapter 8 omake'), 8.98);
      expect(parse('Title', 'Chapter 8 special'), 8.97);
    });

    test('a single alpha suffix maps a->.1, b->.2', () {
      expect(parse('Title', 'Chapter 7a'), 7.1);
      expect(parse('Title', 'Chapter 7b'), 7.2);
    });

    test('past i there is no room in the first decimal place', () {
      expect(parse('Title', 'Chapter 7j'), 7.0);
    });
  });

  group('the title is stripped before reading digits', () {
    test('digits in the series name are not the chapter number', () {
      expect(parse('Nisekoi 2', 'Nisekoi 2 - 14'), 14.0);
    });

    test('an empty title strips nothing rather than shredding the name', () {
      // Dart's `replaceAll('', x)` inserts between every character; a manga row
      // that has gone missing must not turn the name into confetti.
      expect(parse('', 'Chapter 21'), 21.0);
    });
  });

  test('a name with no digits at all falls back to what was passed in', () {
    expect(parse('Title', 'Prologue'), -1.0);
    expect(parse('Title', 'Prologue', -1.0), -1.0);
  });

  test('commas and hyphens read as decimal points, as in the fork', () {
    expect(parse('Title', 'Chapter 5,5'), 5.5);
  });
}
