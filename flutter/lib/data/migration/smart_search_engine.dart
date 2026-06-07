import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_manga.dart';

/// A search query executed against a single source, returning that source's
/// raw listing for the query.
typedef SearchAction = Future<List<SourceManga>> Function(String query);

/// Dart port of Mihon's `BaseSmartSearchEngine` + `SmartSourceSearchEngine`.
///
/// Given a source manga's title, finds the best-matching entry on a target
/// source by similarity (normalized Levenshtein). `regularSearch` does a
/// single straight search; `deepSearch` cleans the title and fans out across
/// several derived queries (whole title, two largest words, largest word,
/// first two words, first word) for a wider net.
class SmartSearchEngine {
  SmartSearchEngine({
    this.extraSearchParams,
    this.eligibleThreshold = minEligibleThreshold,
  });

  /// Appended to every query when non-blank (Mihon's "additional keywords").
  final String? extraSearchParams;
  final double eligibleThreshold;

  static const double minEligibleThreshold = 0.4;

  static final RegExp _titleRegex = RegExp('[^a-zA-Z0-9- ]');
  static final RegExp _titleCyrillicRegex = RegExp(r'[^\p{L}0-9- ]', unicode: true);
  static final RegExp _consecutiveSpacesRegex = RegExp(' +');
  static final RegExp _chapterRefCyrillicRegexp =
      RegExp(r'((- часть|- глава) \d*)');

  Future<SourceManga?> regularSearch(MangaSource source, String title) {
    return _baseSearch(
      _makeSearchAction(source),
      [title],
      (candidate) => _similarity(title, candidate.title),
    );
  }

  Future<SourceManga?> deepSearch(MangaSource source, String title) {
    final cleanedTitle = _cleanDeepSearchTitle(title);
    final queries = _getDeepSearchQueries(cleanedTitle);
    return _baseSearch(
      _makeSearchAction(source),
      queries,
      (candidate) {
        final cleanedCandidate = _cleanDeepSearchTitle(candidate.title);
        return _similarity(cleanedTitle, cleanedCandidate);
      },
    );
  }

  SearchAction _makeSearchAction(MangaSource source) {
    return (query) async {
      final page = await source.fetchSearch(query, 1);
      return page.mangas;
    };
  }

  Future<SourceManga?> _baseSearch(
    SearchAction searchAction,
    List<String> queries,
    double Function(SourceManga) calculateDistance,
  ) async {
    final results = await Future.wait(
      queries.map((query) async {
        final builtQuery =
            (extraSearchParams != null && extraSearchParams!.trim().isNotEmpty)
                ? '$query ${extraSearchParams!}'
                : query;
        final List<SourceManga> candidates;
        try {
          candidates = await searchAction(builtQuery);
        } catch (_) {
          return const <_SearchEntry>[];
        }
        return candidates
            .map((c) {
              final distance = (queries.length > 1 || candidates.length > 1)
                  ? calculateDistance(c)
                  : 1.0;
              return _SearchEntry(c, distance);
            })
            .where((e) => e.distance >= eligibleThreshold)
            .toList();
      }),
    );

    _SearchEntry? best;
    for (final list in results) {
      for (final entry in list) {
        if (best == null || entry.distance > best.distance) {
          best = entry;
        }
      }
    }
    return best?.entry;
  }

  String _cleanDeepSearchTitle(String title) {
    final preTitle = title.toLowerCase();

    // Remove text in brackets.
    var cleanedTitle = _removeTextInBrackets(preTitle, true);
    if (cleanedTitle.length <= 5) {
      // Suspiciously short — try parsing backwards.
      cleanedTitle = _removeTextInBrackets(preTitle, false);
    }

    // Strip Cyrillic chapter references.
    cleanedTitle =
        cleanedTitle.replaceAll(_chapterRefCyrillicRegexp, ' ').trim();

    // Strip non-special characters.
    final cleanedTitleEng = cleanedTitle.replaceAll(_titleRegex, ' ');

    // Don't strip foreign-language letters if the English-only form is short.
    cleanedTitle = cleanedTitleEng.length <= 5
        ? cleanedTitle.replaceAll(_titleCyrillicRegex, ' ')
        : cleanedTitleEng;

    // Strip splitters and collapse spaces.
    cleanedTitle = cleanedTitle
        .trim()
        .replaceAll(' - ', ' ')
        .replaceAll(_consecutiveSpacesRegex, ' ')
        .trim();

    return cleanedTitle;
  }

  String _removeTextInBrackets(String text, bool readForward) {
    final openingChars = readForward ? '([<{' : ')]}>';
    final closingChars = readForward ? ')]}>' : '([<{';
    var depth = 0;
    final buffer = StringBuffer();
    final source = readForward ? text : text.split('').reversed.join();
    for (final char in source.split('')) {
      if (openingChars.contains(char)) {
        depth++;
      } else if (closingChars.contains(char)) {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        buffer.write(char);
      }
    }
    final result = buffer.toString();
    return readForward ? result : result.split('').reversed.join();
  }

  List<String> _getDeepSearchQueries(String cleanedTitle) {
    final split = cleanedTitle.split(' ');
    if (cleanedTitle.isEmpty || split.isEmpty) return const <String>[];
    final byLargest = [...split]..sort((a, b) => b.length.compareTo(a.length));

    final searchQueries = <List<String>>[
      [cleanedTitle],
      byLargest.take(2).toList(),
      byLargest.take(1).toList(),
      split.take(2).toList(),
      split.take(1).toList(),
    ];

    final seen = <String>{};
    final out = <String>[];
    for (final q in searchQueries) {
      final joined = q.join(' ').trim();
      if (seen.add(joined)) out.add(joined);
    }
    return out;
  }

  /// Normalized Levenshtein similarity in [0, 1]: 1 - distance / maxLength.
  /// Matches `com.aallam.similarity.NormalizedLevenshtein.similarity`.
  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - _levenshtein(a, b) / maxLen;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final deletion = previous[j + 1] + 1;
        final insertion = current[j] + 1;
        final substitution = previous[j] + cost;
        var min = deletion < insertion ? deletion : insertion;
        if (substitution < min) min = substitution;
        current[j + 1] = min;
      }
      final tmp = previous;
      previous = current;
      current = tmp;
    }
    return previous[b.length];
  }
}

class _SearchEntry {
  const _SearchEntry(this.entry, this.distance);

  final SourceManga entry;
  final double distance;
}
