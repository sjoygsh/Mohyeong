/// Lightweight manga representation returned by a source's listing endpoints
/// (popular / latest / search). Mirrors Kotlin's `SManga` interface.
///
/// `url` is the source-internal manga path (the source decides what to do
/// with it — typically a path under `baseUrl`). It is the stable key the
/// source uses to look up the manga again for details/chapter listing.
class SourceManga {
  const SourceManga({
    required this.url,
    required this.title,
    this.author,
    this.artist,
    this.description,
    this.genre,
    this.status = 0,
    this.thumbnailUrl,
    this.initialized = false,
  });

  final String url;
  final String title;
  final String? author;
  final String? artist;
  final String? description;
  final String? genre;
  // Mirrors SManga.STATUS_* (0=Unknown, 1=Ongoing, 2=Completed, 3=Licensed,
  // 4=Publishing Finished, 5=Cancelled, 6=On Hiatus).
  final int status;
  final String? thumbnailUrl;
  // True once fetchMangaDetails has populated the optional fields. Listings
  // return uninitialized entries; details() fills them in.
  final bool initialized;

  SourceManga copyWith({
    String? url,
    String? title,
    String? author,
    String? artist,
    String? description,
    String? genre,
    int? status,
    String? thumbnailUrl,
    bool? initialized,
  }) {
    return SourceManga(
      url: url ?? this.url,
      title: title ?? this.title,
      author: author ?? this.author,
      artist: artist ?? this.artist,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      status: status ?? this.status,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      initialized: initialized ?? this.initialized,
    );
  }

  factory SourceManga.fromJson(Map<String, dynamic> json) => SourceManga(
        url: json['url'] as String,
        title: json['title'] as String,
        author: json['author'] as String?,
        artist: json['artist'] as String?,
        description: json['description'] as String?,
        genre: json['genre'] as String?,
        status: (json['status'] as num?)?.toInt() ?? 0,
        thumbnailUrl: json['thumbnail_url'] as String?,
        initialized: json['initialized'] as bool? ?? false,
      );
}

/// One page of search/listing results.
class MangasPage {
  const MangasPage({required this.mangas, required this.hasNextPage});

  final List<SourceManga> mangas;
  final bool hasNextPage;

  factory MangasPage.fromJson(Map<String, dynamic> json) => MangasPage(
        mangas: (json['mangas'] as List<dynamic>)
            .map((e) => SourceManga.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        hasNextPage: json['has_next_page'] as bool? ?? false,
      );
}
