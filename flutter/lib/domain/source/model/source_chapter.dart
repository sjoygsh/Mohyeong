/// Chapter representation returned by a source's chapter list. Mirrors
/// Kotlin's `SChapter` interface. Once persisted these get converted into
/// the stored `Chapter` domain model in `domain/chapter/model/chapter.dart`.
class SourceChapter {
  const SourceChapter({
    required this.url,
    required this.name,
    this.dateUpload = 0,
    this.chapterNumber = -1,
    this.volumeNumber,
    this.scanlator,
  });

  final String url;
  final String name;
  final int dateUpload;
  final double chapterNumber;
  final double? volumeNumber;
  final String? scanlator;

  factory SourceChapter.fromJson(Map<String, dynamic> json) => SourceChapter(
        url: json['url'] as String,
        name: json['name'] as String,
        dateUpload: (json['date_upload'] as num?)?.toInt() ?? 0,
        chapterNumber: (json['chapter_number'] as num?)?.toDouble() ?? -1,
        volumeNumber: (json['volume_number'] as num?)?.toDouble(),
        scanlator: json['scanlator'] as String?,
      );
}

/// A single page of an opened chapter. Mirrors Kotlin's `Page`.
///
/// `imageUrl` may be null on first delivery — sources sometimes resolve the
/// image URL lazily via `fetchImageUrl`. For now the JS extension is expected
/// to return the resolved imageUrl in one pass.
class SourcePage {
  const SourcePage({
    required this.index,
    required this.url,
    this.imageUrl,
    this.headers,
  });

  /// Zero-based page index within the chapter.
  final int index;

  /// Source-internal page URL (e.g. an HTML viewer page) — used for the
  /// lazy-resolve path. Often equals `imageUrl` when no resolve step exists.
  final String url;

  /// The actual image URL the reader displays. Optional only because of the
  /// lazy-resolve case; the reader treats null as "needs resolve".
  final String? imageUrl;

  /// Per-request headers for the image fetch (Referer, User-Agent, ...).
  /// Many sources require a matching Referer or images 403.
  final Map<String, String>? headers;

  factory SourcePage.fromJson(Map<String, dynamic> json) => SourcePage(
        index: (json['index'] as num).toInt(),
        url: json['url'] as String,
        imageUrl: json['image_url'] as String?,
        headers: (json['headers'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
      );
}
