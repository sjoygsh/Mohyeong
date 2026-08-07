/// Derives a chapter number from a chapter's name when the source doesn't
/// supply one — a 1:1 port of Kotlin
/// `tachiyomi/domain/chapter/service/ChapterRecognition.kt`.
///
/// Mihon runs this on every chapter as it syncs, and this port never did: the
/// number the extension returned was stored verbatim. Most extensions here
/// return nothing — both shared theme factories in `_mhThemeLib` emit a
/// literal `chapter_number: -1`, and they back half the installed corpus — so
/// most of the library had -1 in that column for every row. Everything keyed on
/// the chapter number quietly did nothing as a result: sort-by-chapter-number
/// was one giant tie, gap detection found no gaps, linked-source chapters
/// couldn't be merged, and the duplicate-chapter rules (which all test
/// `chapterNumber >= 0`) never fired.
library;

// `([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?` — integer, optional decimal, optional
// alphabetic suffix ("5.5", "12b", "7 extra").
const String _numberPattern = r'([0-9]+)(\.[0-9]+)?(\.?[a-z]+)?';

/// "Mokushiroku Alice Vol.1 Ch. 4: Misrepresentation" -> 4
final RegExp _basic = RegExp('(?<=ch\\.) *$_numberPattern');

/// "Bleach 567: Down With Snowwhite" -> 567
final RegExp _number = RegExp(_numberPattern);

/// Volume/season markers, so "Prison School 12 v.1 vol004 volume64" -> 12.
final RegExp _unwanted =
    RegExp(r'\b(?:v|ver|vol|version|volume|season|s)[^a-z]?[0-9]+');

/// "One Piece 12 special" -> "One Piece 12special", so the suffix binds to the
/// number the way [_numberPattern]'s third group expects.
final RegExp _unwantedWhiteSpace = RegExp(r'\s(?=extra|special|omake)');

/// Stands in for an empty manga title so the strip step is a no-op.
final RegExp _neverMatches = RegExp(r'(?!)');

/// The chapter number for [chapterName], or [chapterNumber] when the source
/// already gave a usable one.
///
/// `-2` is Mihon's "deliberately unnumbered" sentinel and is passed through
/// untouched; anything greater than -1 is trusted as supplied. -1 (the default
/// for a source that says nothing) is what sends us to the name.
double parseChapterNumber(
  String mangaTitle,
  String chapterName, {
  double? chapterNumber,
}) {
  if (chapterNumber != null && (chapterNumber == -2.0 || chapterNumber > -1.0)) {
    return chapterNumber;
  }

  final lowerTitle = mangaTitle.toLowerCase();
  final cleanChapterName = chapterName
      .toLowerCase()
      // The series title is not part of its chapter numbering — "Bleach 567"
      // must not read the 567 out of a title that contains digits. Guarded on
      // empty: Dart's `replaceAll('', x)` inserts x between EVERY character.
      .replaceAll(lowerTitle.isEmpty ? _neverMatches : lowerTitle, '')
      .trim()
      .replaceAll(',', '.')
      .replaceAll('-', '.')
      .replaceAll(_unwantedWhiteSpace, '');

  final matches = _number.allMatches(cleanChapterName).toList(growable: false);
  if (matches.isEmpty) return chapterNumber ?? -1.0;

  if (matches.length > 1) {
    final name = cleanChapterName.replaceAll(_unwanted, '');
    final basicMatch = _basic.firstMatch(name);
    if (basicMatch != null) return _fromMatch(basicMatch);
    // The first number may have been one of the tags just removed, so look
    // again in the stripped name before falling back.
    final numberMatch = _number.firstMatch(name);
    if (numberMatch != null) return _fromMatch(numberMatch);
  }

  return _fromMatch(matches.first);
}

double _fromMatch(RegExpMatch match) {
  final initial = double.parse(match.group(1)!);
  return initial + _checkForDecimal(match.group(2), match.group(3));
}

double _checkForDecimal(String? decimal, String? alpha) {
  // Group 2 keeps its leading dot, so ".5" parses straight to 0.5.
  if (decimal != null && decimal.isNotEmpty) return double.parse(decimal);

  if (alpha != null && alpha.isNotEmpty) {
    if (alpha.contains('extra')) return 0.99;
    if (alpha.contains('omake')) return 0.98;
    if (alpha.contains('special')) return 0.97;

    final trimmedAlpha = alpha.replaceFirst(RegExp(r'^\.+'), '');
    if (trimmedAlpha.length == 1) return _parseAlphaPostFix(trimmedAlpha[0]);
  }

  return 0.0;
}

/// x.a -> x.1, x.b -> x.2, and so on. Past 'i' there is no room left in the
/// first decimal place, so it contributes nothing.
double _parseAlphaPostFix(String alpha) {
  final number = alpha.codeUnitAt(0) - ('a'.codeUnitAt(0) - 1);
  if (number >= 10) return 0.0;
  return number / 10.0;
}
