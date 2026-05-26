/// Mirror of `tachiyomi.domain.chapter.model.Chapter`.
class Chapter {
  const Chapter({
    required this.id,
    required this.mangaId,
    required this.read,
    required this.bookmark,
    required this.lastPageRead,
    required this.dateFetch,
    required this.sourceOrder,
    required this.url,
    required this.name,
    required this.dateUpload,
    required this.chapterNumber,
    required this.scanlator,
    required this.lastModifiedAt,
    required this.version,
    this.bookmarkNote,
    this.volumeNumber,
  });

  final int id;
  final int mangaId;
  final bool read;
  final bool bookmark;
  final int lastPageRead;
  final int dateFetch;
  final int sourceOrder;
  final String url;
  final String name;
  final int dateUpload;
  final double chapterNumber;
  final String? scanlator;
  final int lastModifiedAt;
  final int version;
  final String? bookmarkNote;
  final double? volumeNumber;

  bool get isRecognizedNumber => chapterNumber >= 0;
  bool get isRecognizedVolume => volumeNumber != null && volumeNumber! >= 0;

  /// Mirrors Kotlin's `copyFrom` -- pulls source-derived fields from another
  /// Chapter while keeping local state (read/bookmark/etc.).
  Chapter copyFrom(Chapter other) {
    return copyWith(
      name: other.name,
      url: other.url,
      dateUpload: other.dateUpload,
      chapterNumber: other.chapterNumber,
      // Blank scanlator strings normalise to null, matching the Kotlin
      // `other.scanlator?.ifBlank { null }`.
      scanlator: () {
        final s = other.scanlator;
        if (s == null) return null;
        if (s.trim().isEmpty) return null;
        return s;
      }(),
    );
  }

  Chapter copyWith({
    int? id,
    int? mangaId,
    bool? read,
    bool? bookmark,
    int? lastPageRead,
    int? dateFetch,
    int? sourceOrder,
    String? url,
    String? name,
    int? dateUpload,
    double? chapterNumber,
    Object? scanlator = _sentinel,
    int? lastModifiedAt,
    int? version,
    Object? bookmarkNote = _sentinel,
    Object? volumeNumber = _sentinel,
  }) {
    return Chapter(
      id: id ?? this.id,
      mangaId: mangaId ?? this.mangaId,
      read: read ?? this.read,
      bookmark: bookmark ?? this.bookmark,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      dateFetch: dateFetch ?? this.dateFetch,
      sourceOrder: sourceOrder ?? this.sourceOrder,
      url: url ?? this.url,
      name: name ?? this.name,
      dateUpload: dateUpload ?? this.dateUpload,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      scanlator: identical(scanlator, _sentinel)
          ? this.scanlator
          : scanlator as String?,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      version: version ?? this.version,
      bookmarkNote: identical(bookmarkNote, _sentinel)
          ? this.bookmarkNote
          : bookmarkNote as String?,
      volumeNumber: identical(volumeNumber, _sentinel)
          ? this.volumeNumber
          : volumeNumber as double?,
    );
  }

  factory Chapter.empty() => const Chapter(
        id: -1,
        mangaId: -1,
        read: false,
        bookmark: false,
        lastPageRead: 0,
        dateFetch: 0,
        sourceOrder: 0,
        url: '',
        name: '',
        dateUpload: -1,
        chapterNumber: -1,
        scanlator: null,
        lastModifiedAt: 0,
        version: 1,
        bookmarkNote: null,
        volumeNumber: null,
      );
}

const Object _sentinel = Object();
