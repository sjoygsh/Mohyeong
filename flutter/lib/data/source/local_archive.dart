/// Reads image pages out of CBZ / ZIP archive chapters for the Local source.
///
/// Mihon's `LocalSource` treats a `.cbz` / `.zip` (and several other formats)
/// sitting inside a manga folder as a single chapter, unzipping its images on
/// demand. This is the Flutter equivalent for the two dominant formats. The
/// archive bytes are pulled either through the SAF channel (`content://`
/// document URI on Android) or `dart:io` (a filesystem path on desktop), then
/// decoded once and cached so that paging through a chapter doesn't re-unzip
/// the whole file on every page.
///
/// RAR/CBR/7z/TAR/EPUB are intentionally out of scope here — there is no
/// pure-Dart decoder for them and Mihon leans on native libs for those.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'saf.dart';

/// Archive container extensions recognised as a single chapter.
const List<String> kArchiveExts = ['.cbz', '.zip'];

/// Image extensions extracted from an archive as pages.
const List<String> _imageExts = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.avif',
];

/// True when [locator] points at an archive container (by extension), whether
/// it's a `content://` document URI or a plain filesystem path. Extensions
/// survive percent-encoding (letters/dots aren't escaped) so this works for
/// both backends.
bool isArchiveLocator(String locator) {
  final lower = locator.toLowerCase();
  for (final ext in kArchiveExts) {
    if (lower.endsWith(ext)) return true;
  }
  return false;
}

/// True for a file name (not a full locator) ending in an archive extension.
bool isArchiveName(String name) =>
    kArchiveExts.contains(p.extension(name).toLowerCase());

/// Page-image URL scheme understood by `SourceImage`. Encodes the archive
/// locator and the entry name with base64url so neither can collide with the
/// `/` separator or leak characters that confuse the image layer.
const String _scheme = 'archive://';

String encodeArchivePageUrl(String locator, String entry) =>
    '$_scheme${base64Url.encode(utf8.encode(locator))}'
    '/${base64Url.encode(utf8.encode(entry))}';

bool isArchivePageUrl(String url) => url.startsWith(_scheme);

({String locator, String entry}) decodeArchivePageUrl(String url) {
  final rest = url.substring(_scheme.length);
  final slash = rest.indexOf('/');
  final locator = utf8.decode(base64Url.decode(rest.substring(0, slash)));
  final entry = utf8.decode(base64Url.decode(rest.substring(slash + 1)));
  return (locator: locator, entry: entry);
}

/// Small LRU of decoded archives: locator → (entry name → bytes). Capped so a
/// couple of chapters stay hot without the whole library piling up in memory.
class _ArchiveCache {
  _ArchiveCache(this._capacity);

  final int _capacity;
  final LinkedHashMap<String, Map<String, Uint8List>> _map =
      LinkedHashMap<String, Map<String, Uint8List>>();

  Map<String, Uint8List>? get(String key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v; // mark most-recently-used
    return v;
  }

  void put(String key, Map<String, Uint8List> value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > _capacity) {
      _map.remove(_map.keys.first);
    }
  }
}

final _ArchiveCache _cache = _ArchiveCache(2);

Future<Uint8List?> _readArchiveBytes(String locator) async {
  if (Saf.isContentUri(locator)) {
    return Saf.readBytes(locator);
  }
  final path =
      locator.startsWith('file://') ? Uri.parse(locator).toFilePath() : locator;
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

/// In-flight decodes, so two pages of the same archive requested together
/// share one isolate run instead of decompressing the file twice.
final Map<String, Future<Map<String, Uint8List>>> _inFlight = {};

/// ZIP decode + image-entry decompression. Top-level so [Isolate.run] can
/// invoke it — running this on the UI isolate froze scrolling for the
/// duration of a whole-chapter unzip (a multi-hundred-ms stall on a
/// multi-MB CBZ).
Map<String, Uint8List> _decodeArchiveEntries(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entries = <String, Uint8List>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    final ext = p.extension(file.name).toLowerCase();
    if (!_imageExts.contains(ext)) continue;
    final content = file.readBytes();
    if (content != null) {
      entries[file.name] = Uint8List.fromList(content);
    }
  }
  return entries;
}

/// Decodes [locator] (or returns the cached map) into entry-name → bytes for
/// every image entry, skipping directories and non-image files. The
/// decompression itself runs in a background isolate.
Future<Map<String, Uint8List>> _loadArchive(String locator) async {
  final cached = _cache.get(locator);
  if (cached != null) return cached;

  final pending = _inFlight[locator];
  if (pending != null) return pending;

  final future = () async {
    final bytes = await _readArchiveBytes(locator);
    if (bytes == null) return const <String, Uint8List>{};
    final entries = await Isolate.run(() => _decodeArchiveEntries(bytes));
    _cache.put(locator, entries);
    return entries;
  }();
  _inFlight[locator] = future;
  try {
    return await future;
  } finally {
    _inFlight.remove(locator);
  }
}

/// The image entry names inside an archive chapter, unsorted (the caller
/// applies its own natural sort to match the folder-chapter ordering).
Future<List<String>> listArchiveImageEntries(String locator) async {
  final entries = await _loadArchive(locator);
  return entries.keys.toList(growable: false);
}

/// The decoded bytes of a single archive entry, for the image provider.
Future<Uint8List?> readArchiveEntry(String locator, String entry) async {
  final entries = await _loadArchive(locator);
  return entries[entry];
}
