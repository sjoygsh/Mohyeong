import 'source_chapter.dart';
import 'source_manga.dart';

/// Interface for a single manga source/extension. The Dart-side facade over
/// either a JS-backed extension or a built-in source. Mirrors Kotlin's
/// `Source` / `CatalogueSource` interface, flattened (no separate HttpSource /
/// ParsedHttpSource — those distinctions live inside the JS extension itself).
abstract class MangaSource {
  /// Stable identifier (e.g. `mangadex`, `comick`). Must be unique across
  /// installed extensions.
  String get id;

  /// Human-readable name shown in the browse / sources picker.
  String get name;

  /// Two-letter language code (`en`, `ja`, ...) or `all` for multi-language
  /// sources.
  String get lang;

  /// Base URL the source talks to. Used for opening the source in an
  /// external browser and for relative-URL resolution.
  String get baseUrl;

  /// Increments when the extension publishes a breaking change. Used by the
  /// extension-update UI.
  int get versionCode;

  /// Some sources don't expose a "latest" feed.
  bool get supportsLatest;

  Future<MangasPage> fetchPopular(int page);
  Future<MangasPage> fetchLatest(int page);
  Future<MangasPage> fetchSearch(String query, int page);

  /// Fills in the optional fields on a [SourceManga] returned by listings.
  Future<SourceManga> fetchMangaDetails(SourceManga manga);

  Future<List<SourceChapter>> fetchChapterList(SourceManga manga);
  Future<List<SourcePage>> fetchPageList(SourceChapter chapter);

  /// Absolute URL of the chapter's web page, for the reader's "Open in
  /// WebView" / "Open in browser" / "Share" actions. Mirrors Kotlin
  /// `HttpSource.getChapterUrl`: the default joins [baseUrl] with the
  /// relative `chapter.url`; sources whose internal chapter URLs aren't
  /// web paths (e.g. bare API ids) override it. Returns null when no web
  /// URL can be produced.
  Future<String?> getChapterUrl(SourceChapter chapter) async {
    var full = chapter.url;
    if (!full.startsWith('http')) {
      if (baseUrl.isEmpty) return null;
      full = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
          '/${full.replaceAll(RegExp(r'^/+'), '')}';
    }
    final uri = Uri.tryParse(full);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return full;
  }

  /// Disposes any underlying resources (JS engines, HTTP clients). Called
  /// when the user uninstalls the extension or the source repo is rebuilt.
  Future<void> dispose() async {}
}
