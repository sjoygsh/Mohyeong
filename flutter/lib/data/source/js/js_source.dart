import 'package:dio/dio.dart';

import '../../../domain/source/model/manga_source.dart';
import '../../../domain/source/model/source_chapter.dart';
import '../../../domain/source/model/source_manga.dart';
import 'js_runtime.dart';

/// [MangaSource] implementation backed by a JS extension running inside a
/// [JsRuntime]. The extension must register `__extension` with a manifest +
/// the popular/latest/search/details/chapters/pages methods.
class JsSource implements MangaSource {
  JsSource._({required this.manifest, required this.runtime});

  /// Constructs a [JsSource] by loading the JS source string into a fresh
  /// [JsRuntime] and reading the manifest the extension registers.
  static Future<JsSource> load(
    String jsSource, {
    required Dio dio,
    void Function(String level, String message)? onLog,
  }) async {
    final runtime = JsRuntime(dio: dio, onLog: onLog);
    try {
      await runtime.loadExtensionSource(jsSource);
      final manifest = runtime.readManifest();
      return JsSource._(manifest: manifest, runtime: runtime);
    } catch (_) {
      runtime.dispose();
      rethrow;
    }
  }

  final Map<String, dynamic> manifest;
  final JsRuntime runtime;

  @override
  String get id => manifest['id'] as String;

  @override
  String get name => manifest['name'] as String;

  @override
  String get lang => manifest['lang'] as String? ?? 'all';

  @override
  String get baseUrl => manifest['base_url'] as String? ?? '';

  @override
  int get versionCode => (manifest['version_code'] as num?)?.toInt() ?? 1;

  @override
  bool get supportsLatest => manifest['supports_latest'] as bool? ?? false;

  @override
  Future<MangasPage> fetchPopular(int page) async {
    final result = await runtime.invoke('popular', [page]);
    return MangasPage.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<MangasPage> fetchLatest(int page) async {
    if (!supportsLatest) {
      throw UnsupportedError('Source $id does not support latest feed');
    }
    final result = await runtime.invoke('latest', [page]);
    return MangasPage.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<MangasPage> fetchSearch(String query, int page) async {
    final result = await runtime.invoke('search', [query, page]);
    return MangasPage.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<SourceManga> fetchMangaDetails(SourceManga manga) async {
    final result = await runtime.invoke('details', [
      {
        'url': manga.url,
        'title': manga.title,
        'thumbnail_url': manga.thumbnailUrl,
      },
    ]);
    final m = SourceManga.fromJson(result as Map<String, dynamic>);
    return m.copyWith(url: manga.url, initialized: true);
  }

  @override
  Future<List<SourceChapter>> fetchChapterList(SourceManga manga) async {
    final result = await runtime.invoke('chapters', [
      {'url': manga.url},
    ]);
    return (result as List<dynamic>)
        .map((e) => SourceChapter.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<SourcePage>> fetchPageList(SourceChapter chapter) async {
    final result = await runtime.invoke('pages', [
      {'url': chapter.url},
    ]);
    return (result as List<dynamic>)
        .map((e) => SourcePage.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> dispose() async => runtime.dispose();
}
