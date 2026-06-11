import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_chapter.dart';
import '../../domain/source/model/source_manga.dart';
import 'local_archive.dart';
import 'local_source_preferences.dart';
import 'saf.dart';

/// Local manga source. Walks a user-configured root and presents its layout
/// as a regular [MangaSource].
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
/// ## Two backends
///
/// The configured root can be either:
///
///  * a `content://` SAF tree URI (Android, the normal case) — walked via
///    the native [Saf] channel. `DocumentsContract` gives us no stable
///    filesystem path, so here a manga/chapter/page `url` IS its tree-based
///    document URI. Those URIs stay valid across sessions as long as the
///    persisted tree permission survives, so storing them on library rows
///    is safe.
///
///  * a filesystem path (desktop, or the legacy `pref_local_source_root`) —
///    walked with `dart:io`. Here `url`s are folder names relative to their
///    parent, exactly as the first Flutter cut did, and pages/covers come
///    back as `file://` URIs.
///
/// [SourceImage] renders both `content://` (via the SAF channel) and
/// `file://` (via `Image.file`) uniformly, so the reader is backend-blind.
///
/// A chapter can be either a folder of images (as drawn above) or a single
/// `.cbz` / `.zip` archive sitting next to the cover. Archive chapters are
/// unzipped on demand (see [local_archive.dart]); pages inside them are
/// served as `archive://` URLs that [SourceImage] decodes. RAR/CBR/7z/EPUB
/// are not supported (no pure-Dart decoder).
class LocalSource extends MangaSource {
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

  static const List<String> _coverNames = [
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'cover.webp',
  ];

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

  bool get _isSaf {
    final root = _prefs.root;
    return root != null && Saf.isContentUri(root);
  }

  // ---------------------------------------------------------------------------
  // Public source API — dispatches to the SAF or filesystem implementation.
  // ---------------------------------------------------------------------------

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
  Future<MangasPage> fetchSearch(
    String query,
    int page, {
    Map<String, String>? filters,
  }) async {
    if (page > 1) return const MangasPage(mangas: [], hasNextPage: false);
    final all = await _listAllManga();
    final q = query.toLowerCase();
    final filtered = all
        .where((m) => m.title.toLowerCase().contains(q))
        .toList(growable: false);
    return MangasPage(mangas: filtered, hasNextPage: false);
  }

  @override
  Future<SourceManga> fetchMangaDetails(SourceManga manga) async {
    if (_isSaf) {
      final cover = await _safCover(manga.url);
      return SourceManga(
        url: manga.url,
        title: manga.title,
        thumbnailUrl: cover ?? manga.thumbnailUrl,
        initialized: true,
      );
    }
    final root = _rootDir();
    if (root == null) return manga;
    final dir = Directory(p.join(root.path, manga.url));
    if (!dir.existsSync()) return manga;
    return _mangaFromDir(dir);
  }

  @override
  Future<List<SourceChapter>> fetchChapterList(SourceManga manga) async {
    if (_isSaf) return _safChapterList(manga.url);
    final root = _rootDir();
    if (root == null) return const [];
    final mangaDir = Directory(p.join(root.path, manga.url));
    if (!mangaDir.existsSync()) return const [];
    // Chapters are sub-folders of images or .cbz/.zip archive files.
    final chapterEntries = mangaDir
        .listSync(followLinks: false)
        .where((e) => e is Directory || isArchiveName(p.basename(e.path)))
        .toList()
      ..sort((a, b) =>
          _naturalCompare(p.basename(b.path), p.basename(a.path)));
    final result = <SourceChapter>[];
    for (final entry in chapterEntries) {
      final basename = p.basename(entry.path);
      final String name;
      if (entry is Directory) {
        // Empty-of-pages chapters are filtered so the user doesn't see a
        // chapter tile that opens to a blank reader.
        if (_imageFilesIn(entry).isEmpty) continue;
        name = basename;
      } else {
        name = p.basenameWithoutExtension(basename);
      }
      final stat = await entry.stat();
      result.add(SourceChapter(
        url: basename,
        name: name,
        chapterNumber: _parseChapterNumber(name),
        dateUpload: stat.modified.millisecondsSinceEpoch,
      ));
    }
    return result;
  }

  @override
  Future<List<SourcePage>> fetchPageList(SourceChapter chapter) async {
    if (_isSaf) {
      // In SAF mode chapter.url is the chapter folder's document URI, so we
      // can list its pages directly — no whole-root search needed.
      return _safPages(chapter.url);
    }
    final root = _rootDir();
    if (root == null) return const [];
    // chapter.url is relative to the manga folder which we don't know here,
    // so rebuild the absolute path by searching the root for a chapter dir or
    // archive file matching the chapter url.
    for (final mangaEntry in root.listSync(followLinks: false)) {
      if (mangaEntry is! Directory) continue;
      final candidate = p.join(mangaEntry.path, chapter.url);
      if (isArchiveName(chapter.url)) {
        if (File(candidate).existsSync()) return _archivePages(candidate);
      } else if (Directory(candidate).existsSync()) {
        return _pagesFromDir(Directory(candidate));
      }
    }
    return const [];
  }

  /// Reader-facing helper: resolves the page list for a specific manga +
  /// chapter pair, without the "search the whole root" fallback in
  /// [fetchPageList].
  Future<List<SourcePage>> pagesForChapter(
      String mangaUrl, String chapterUrl) async {
    if (_isSaf) return _safPages(chapterUrl);
    final root = _rootDir();
    if (root == null) return const [];
    final path = p.join(root.path, mangaUrl, chapterUrl);
    if (isArchiveName(chapterUrl)) {
      if (!File(path).existsSync()) return const [];
      return _archivePages(path);
    }
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    return _pagesFromDir(dir);
  }

  // ---------------------------------------------------------------------------
  // SAF backend (content:// tree URIs).
  // ---------------------------------------------------------------------------

  Future<List<SourceManga>> _safListAllManga() async {
    final root = _prefs.root;
    if (root == null) return const [];
    final children = await _safMangaRootChildren(root);
    final mangaDirs = children.where((e) => e.isDir).toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    final mangas = <SourceManga>[];
    for (final dir in mangaDirs) {
      final cover = await _safCover(dir.uri);
      mangas.add(SourceManga(
        url: dir.uri,
        title: dir.name,
        thumbnailUrl: cover,
        initialized: true,
      ));
    }
    return mangas;
  }

  /// The configured storage dir is Mihon's *base* directory; local manga
  /// live under a `local` sub-folder of it (alongside `downloads`,
  /// `autobackup`). Resolve that sub-folder and return its children. If
  /// there's no `local` child the picked folder is treated as the manga
  /// root directly, so a user who points straight at a manga collection
  /// still works.
  Future<List<SafEntry>> _safMangaRootChildren(String rootUri) async {
    final topLevel = await Saf.listChildren(rootUri);
    for (final e in topLevel) {
      if (e.isDir && e.name.toLowerCase() == 'local') {
        return Saf.listChildren(e.uri);
      }
    }
    return topLevel;
  }

  /// Resolves a cover for a manga folder URI: an explicit `cover.*` file,
  /// else the first image of the first chapter folder.
  Future<String?> _safCover(String mangaUri) async {
    final children = await Saf.listChildren(mangaUri);
    for (final e in children) {
      if (!e.isDir && _coverNames.contains(e.name.toLowerCase())) {
        return e.uri;
      }
    }
    // No explicit cover.* — fall back to the first page of the first chapter,
    // which may be a folder or an archive.
    final chapters = children
        .where((e) => e.isDir || isArchiveName(e.name))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    for (final c in chapters) {
      if (c.isDir) {
        final pages = await _safImageEntries(c.uri);
        if (pages.isNotEmpty) return pages.first.uri;
      } else {
        final names = await listArchiveImageEntries(c.uri);
        if (names.isNotEmpty) {
          names.sort(_naturalCompare);
          return encodeArchivePageUrl(c.uri, names.first);
        }
      }
    }
    return null;
  }

  Future<List<SourceChapter>> _safChapterList(String mangaUri) async {
    final children = await Saf.listChildren(mangaUri);
    // A chapter is either a sub-folder of images or a .cbz/.zip archive file.
    final chapters = children
        .where((e) => e.isDir || isArchiveName(e.name))
        .toList()
      // Reverse natural order so newest-numbered chapters surface first,
      // matching the filesystem path.
      ..sort((a, b) => _naturalCompare(b.name, a.name));
    final result = <SourceChapter>[];
    for (final entry in chapters) {
      // Archive chapters are included unconditionally — peeking inside every
      // archive just to count pages would make listing prohibitively slow.
      // Folder chapters keep the empty-folder filter so we don't surface a
      // tile that opens to a blank reader.
      final String name;
      if (entry.isDir) {
        if ((await _safImageEntries(entry.uri)).isEmpty) continue;
        name = entry.name;
      } else {
        name = p.basenameWithoutExtension(entry.name);
      }
      result.add(SourceChapter(
        url: entry.uri,
        name: name,
        chapterNumber: _parseChapterNumber(name),
        // SAF doesn't surface a reliable mtime through the children query;
        // leave dateUpload at 0 (Mihon also tolerates unknown dates here).
        dateUpload: 0,
      ));
    }
    return result;
  }

  Future<List<SourcePage>> _safPages(String chapterUri) async {
    if (isArchiveLocator(chapterUri)) return _archivePages(chapterUri);
    final entries = await _safImageEntries(chapterUri);
    return [
      for (var i = 0; i < entries.length; i++)
        SourcePage(
          index: i,
          url: entries[i].uri,
          imageUrl: entries[i].uri,
        ),
    ];
  }

  /// Pages of a `.cbz` / `.zip` chapter, identified by [archiveLocator] (a
  /// SAF document URI or a filesystem path). Image entries are pulled from
  /// the archive, natural-sorted to match folder ordering, and handed back
  /// as `archive://` URLs the image layer can decode.
  Future<List<SourcePage>> _archivePages(String archiveLocator) async {
    final names = await listArchiveImageEntries(archiveLocator);
    names.sort(_naturalCompare);
    return [
      for (var i = 0; i < names.length; i++)
        SourcePage(
          index: i,
          url: encodeArchivePageUrl(archiveLocator, names[i]),
          imageUrl: encodeArchivePageUrl(archiveLocator, names[i]),
        ),
    ];
  }

  Future<List<SafEntry>> _safImageEntries(String dirUri) async {
    final children = await Saf.listChildren(dirUri);
    final images = children.where((e) {
      if (e.isDir) return false;
      final ext = p.extension(e.name).toLowerCase();
      return _imageExts.contains(ext);
    }).toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    return images;
  }

  // ---------------------------------------------------------------------------
  // Filesystem backend (dart:io paths).
  // ---------------------------------------------------------------------------

  Future<List<SourceManga>> _listAllManga() async {
    if (_isSaf) return _safListAllManga();
    final root = _rootDir();
    if (root == null) return const [];
    final entries = await root.list(followLinks: false).toList();
    final mangas = <SourceManga>[];
    for (final entry in entries) {
      if (entry is! Directory) continue;
      mangas.add(_mangaFromDir(entry));
    }
    mangas.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return mangas;
  }

  Directory? _rootDir() {
    final root = _prefs.root;
    if (root == null || Saf.isContentUri(root)) return null;
    final dir = Directory(root);
    if (!dir.existsSync()) return null;
    return dir;
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
    // Fallback cover: first image of the first chapter (folder or archive).
    if (cover == null) {
      try {
        final children = dir
            .listSync(followLinks: false)
            .where((e) => e is Directory || isArchiveName(p.basename(e.path)))
            .toList()
          ..sort((a, b) =>
              _naturalCompare(p.basename(a.path), p.basename(b.path)));
        for (final c in children) {
          if (c is Directory) {
            final pages = _imageFilesIn(c);
            if (pages.isNotEmpty) {
              cover = pages.first.uri.toString();
              break;
            }
          }
          // Archive covers resolve lazily in the SAF path; for the filesystem
          // listing we only cheaply probe folders. An archive-only manga
          // shows no grid cover until its details screen renders, which is an
          // acceptable trade vs. unzipping every archive during a list walk.
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
    files.sort(
        (a, b) => _naturalCompare(p.basename(a.path), p.basename(b.path)));
    return files;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers.
  // ---------------------------------------------------------------------------

  /// Pulls a leading-number-ish chapter number out of names like
  /// `Chapter 12.5`, `c012`, `12 - title`. Falls back to -1 if nothing
  /// numeric can be found.
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
