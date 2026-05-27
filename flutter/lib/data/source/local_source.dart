import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_chapter.dart';
import '../../domain/source/model/source_manga.dart';
import 'local_source_preferences.dart';

/// Local manga source. Walks a user-configured root directory and
/// presents its layout as a regular [MangaSource].
///
/// Expected layout (matches Mihon's LocalSource convention):
///
///   {root}/
///     My Manga Title/
///       cover.{jpg,png,webp}            (optional explicit cover)
///       Chapter 1/
///         001.jpg
///         002.jpg
///       Chapter 2/
///         ...
///
/// Each top-level directory under `root` is a manga; its `url` is the
/// folder name (relative to root). Each second-level directory is a
/// chapter; its `url` is the chapter folder name (relative to the manga
/// folder). Pages are image files inside the chapter folder, sorted
/// naturally so `page2.jpg` comes before `page10.jpg`.
///
/// Pages and covers are returned as `file://` URIs so they pass through
/// the [SourceImage] / file-path detection in the UI layer.
///
/// CBZ / RAR archives are not supported in this first cut — only loose
/// folders. Users with archives can extract them.
class LocalSource implements MangaSource {
  LocalSource(this._prefs);

  static const String sourceId = '0';

  /// Image extensions we accept as pages. Lowercase comparison.
  static const Set<String> _imageExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };

  final LocalSourcePreferences _prefs;

  @override
  String get id => sourceId;

  @override
  String get name => 'Local source';

  @override
  String get lang => 'other';

  @override
  String get baseUrl => '';

  @override
  int get versionCode => 1;

  @override
  bool get supportsLatest => false;

  Directory? _root() {
    final root = _prefs.root;
    if (root == null) return null;
    final dir = Directory(root);
    if (!dir.existsSync()) return null;
    return dir;
  }

  Future<List<SourceManga>> _listAllManga() async {
    final root = _root();
    if (root == null) return const [];
    final entries = await root.list(followLinks: false).toList();
    final mangas = <SourceManga>[];
    for (final entry in entries) {
      if (entry is! Directory) continue;
      mangas.add(_mangaFromDir(entry));
    }
    mangas.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return mangas;
  }

  SourceManga _mangaFromDir(Directory dir) {
    final title = p.basename(dir.path);
    String? cover;
    for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
      final candidate = File(p.join(dir.path, 'cover.$ext'));
      if (candidate.existsSync()) {
        cover = candidate.uri.toString();
        break;
      }
    }
    // Fallback cover: first image inside the first chapter directory.
    if (cover == null) {
      try {
        final children = dir
            .listSync(followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort((a, b) =>
              _naturalCompare(p.basename(a.path), p.basename(b.path)));
        for (final c in children) {
          final pages = _imageFilesIn(c);
          if (pages.isNotEmpty) {
            cover = pages.first.uri.toString();
            break;
          }
        }
      } catch (_) {
        // Permission denied / IO errors → just leave cover null.
      }
    }
    return SourceManga(
      url: title,
      title: title,
      thumbnailUrl: cover,
      initialized: true,
    );
  }

  @override
  Future<MangasPage> fetchPopular(int page) async {
    if (page > 1) return const MangasPage(mangas: [], hasNextPage: false);
    final all = await _listAllManga();
    return MangasPage(mangas: all, hasNextPage: false);
  }

  @override
  Future<MangasPage> fetchLatest(int page) async {
    // Local source has no notion of "latest" — Mihon hides the tab.
    return const MangasPage(mangas: [], hasNextPage: false);
  }

  @override
  Future<MangasPage> fetchSearch(String query, int page) async {
    if (page > 1) return const MangasPage(mangas: [], hasNextPage: false);
    final all = await _listAllManga();
    final q = query.toLowerCase();
    final filtered =
        all.where((m) => m.title.toLowerCase().contains(q)).toList(growable: false);
    return MangasPage(mangas: filtered, hasNextPage: false);
  }

  @override
  Future<SourceManga> fetchMangaDetails(SourceManga manga) async {
    final root = _root();
    if (root == null) return manga;
    final dir = Directory(p.join(root.path, manga.url));
    if (!dir.existsSync()) return manga;
    return _mangaFromDir(dir);
  }

  @override
  Future<List<SourceChapter>> fetchChapterList(SourceManga manga) async {
    final root = _root();
    if (root == null) return const [];
    final mangaDir = Directory(p.join(root.path, manga.url));
    if (!mangaDir.existsSync()) return const [];
    final chapterDirs = mangaDir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .toList()
      ..sort((a, b) =>
          _naturalCompare(p.basename(b.path), p.basename(a.path)));
    final result = <SourceChapter>[];
    for (var i = 0; i < chapterDirs.length; i++) {
      final dir = chapterDirs[i];
      final basename = p.basename(dir.path);
      // Empty-of-pages chapters are filtered so the user doesn't see a
      // chapter tile that opens to a blank reader.
      if (_imageFilesIn(dir).isEmpty) continue;
      final stat = await dir.stat();
      result.add(SourceChapter(
        url: basename,
        name: basename,
        chapterNumber: _parseChapterNumber(basename),
        dateUpload: stat.modified.millisecondsSinceEpoch,
      ));
    }
    return result;
  }

  @override
  Future<List<SourcePage>> fetchPageList(SourceChapter chapter) async {
    final root = _root();
    if (root == null) return const [];
    // chapter.url is relative to the manga folder which we don't know
    // here — Mihon's chapter url is also opaque-relative, so the reader
    // path stamps the manga url before calling this. We rebuild the
    // absolute path by searching the root for a unique chapter dir
    // matching the chapter url. In practice the reader will resolve
    // chapter paths through [resolveChapterDir] below; this method is
    // only used when called bare (e.g. from the reader scaffold).
    final candidates = <Directory>[];
    for (final mangaEntry in root.listSync(followLinks: false)) {
      if (mangaEntry is! Directory) continue;
      final chapterDir = Directory(p.join(mangaEntry.path, chapter.url));
      if (chapterDir.existsSync()) candidates.add(chapterDir);
    }
    if (candidates.isEmpty) return const [];
    return _pagesFromDir(candidates.first);
  }

  /// Reader-facing helper: resolves the page list for a specific manga +
  /// chapter pair, without the "search the whole root" fallback in
  /// [fetchPageList]. The reader knows both values so this is the path
  /// it should use.
  Future<List<SourcePage>> pagesForChapter(String mangaUrl, String chapterUrl) async {
    final root = _root();
    if (root == null) return const [];
    final dir = Directory(p.join(root.path, mangaUrl, chapterUrl));
    if (!dir.existsSync()) return const [];
    return _pagesFromDir(dir);
  }

  List<SourcePage> _pagesFromDir(Directory dir) {
    final files = _imageFilesIn(dir);
    return [
      for (var i = 0; i < files.length; i++)
        SourcePage(
          index: i,
          url: files[i].uri.toString(),
          imageUrl: files[i].uri.toString(),
        ),
    ];
  }

  List<File> _imageFilesIn(Directory dir) {
    final files = <File>[];
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final ext = p.extension(entry.path).toLowerCase();
      if (_imageExts.contains(ext)) files.add(entry);
    }
    files.sort((a, b) => _naturalCompare(p.basename(a.path), p.basename(b.path)));
    return files;
  }

  /// Pulls a leading-number-ish chapter number out of names like
  /// `Chapter 12.5`, `c012`, `12 - title`. Falls back to -1 if nothing
  /// numeric can be found — the reader still works, but ordering relies
  /// on directory listing.
  double _parseChapterNumber(String name) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(name);
    if (match == null) return -1;
    return double.tryParse(match.group(1)!) ?? -1;
  }

  /// Sorts strings so embedded numbers compare as numbers — e.g.
  /// `page2` < `page10`. Standard "human-friendly" sort.
  int _naturalCompare(String a, String b) {
    final reg = RegExp(r'(\d+)|(\D+)');
    final aParts = reg.allMatches(a).toList();
    final bParts = reg.allMatches(b).toList();
    final n = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < n; i++) {
      final ap = aParts[i].group(0)!;
      final bp = bParts[i].group(0)!;
      final apNum = int.tryParse(ap);
      final bpNum = int.tryParse(bp);
      final int cmp;
      if (apNum != null && bpNum != null) {
        cmp = apNum.compareTo(bpNum);
      } else {
        cmp = ap.toLowerCase().compareTo(bp.toLowerCase());
      }
      if (cmp != 0) return cmp;
    }
    return aParts.length.compareTo(bParts.length);
  }

  @override
  Future<void> dispose() async {}
}
