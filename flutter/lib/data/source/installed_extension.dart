import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk representation of an installed extension.
///
/// Layout under `<appDocuments>/extensions/<id>/`:
///   * `manifest.json` — copy of `__extension.manifest` read from the JS at
///     install time. Lets us list installed extensions without loading every
///     JS engine on app start.
///   * `source.js` — the extension source itself.
///
/// IDs come from the manifest the JS registers. Re-installing with the same
/// ID overwrites the previous version.
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.versionCode,
    required this.supportsLatest,
    required this.sourcePath,
  });

  final String id;
  final String name;
  final String lang;
  final String baseUrl;
  final int versionCode;
  final bool supportsLatest;
  final String sourcePath;

  factory InstalledExtension.fromManifest(
    Map<String, dynamic> manifest,
    String sourcePath,
  ) {
    return InstalledExtension(
      id: manifest['id'] as String,
      name: manifest['name'] as String,
      lang: manifest['lang'] as String? ?? 'all',
      baseUrl: manifest['base_url'] as String? ?? '',
      versionCode: (manifest['version_code'] as num?)?.toInt() ?? 1,
      supportsLatest: manifest['supports_latest'] as bool? ?? false,
      sourcePath: sourcePath,
    );
  }
}

/// Filesystem layout helper. The on-disk index is the source of truth — no
/// Drift table is required (extensions aren't queryable by SQL columns and
/// would only duplicate the manifest).
class ExtensionStorage {
  ExtensionStorage._(this._root);

  final Directory _root;

  static Future<ExtensionStorage> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'extensions'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return ExtensionStorage._(dir);
  }

  Directory _dirFor(String id) => Directory(p.join(_root.path, id));
  File _manifestFile(String id) => File(p.join(_dirFor(id).path, 'manifest.json'));
  File _sourceFile(String id) => File(p.join(_dirFor(id).path, 'source.js'));

  Future<List<InstalledExtension>> listInstalled() async {
    if (!await _root.exists()) return const <InstalledExtension>[];
    final result = <InstalledExtension>[];
    await for (final entity in _root.list()) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      final manifestFile = _manifestFile(id);
      if (!await manifestFile.exists()) continue;
      try {
        final json = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        result.add(InstalledExtension.fromManifest(
          json,
          _sourceFile(id).path,
        ));
      } catch (_) {
        // Ignore corrupt extensions — surfacing them would require a UI we
        // don't have yet. The user can reinstall.
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<String> readSource(String id) async {
    final file = _sourceFile(id);
    if (!await file.exists()) {
      throw StateError('Extension $id is missing its source file');
    }
    return file.readAsString();
  }

  /// Persists an extension to disk. Caller is responsible for having already
  /// loaded the JS source once in a [JsRuntime] to validate it.
  Future<InstalledExtension> install({
    required Map<String, dynamic> manifest,
    required String sourceCode,
  }) async {
    final id = manifest['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError('Manifest missing required `id` field');
    }
    final dir = _dirFor(id);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _manifestFile(id).writeAsString(jsonEncode(manifest));
    await _sourceFile(id).writeAsString(sourceCode);
    return InstalledExtension.fromManifest(manifest, _sourceFile(id).path);
  }

  Future<void> uninstall(String id) async {
    final dir = _dirFor(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
