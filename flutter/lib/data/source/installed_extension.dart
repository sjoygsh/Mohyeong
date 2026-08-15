import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'source_id.dart';

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
    required this.installUrl,
    this.userAgent,
    this.declaredSourceId,
  });

  final String id;
  final String name;
  final String lang;
  final String baseUrl;
  final int versionCode;
  final bool supportsLatest;
  final String sourcePath;

  /// Optional manifest `user_agent`: sent instead of the app default on
  /// image fetches (covers). Needed by hosts that reject browser UAs
  /// (MangaDex requires an identifying UA since mid-2026); mirrors a Kotlin
  /// source overriding `headersBuilder`.
  final String? userAgent;

  /// URL the extension was originally installed from. Null when the
  /// install came from a local file pick (no remembered origin). When
  /// present, the Extensions tab exposes a one-tap "Update" action that
  /// re-fetches this URL through [ExtensionRepository.installFromUrl].
  final String? installUrl;

  /// Manifest `source_id`, when the extension declares one.
  final int? declaredSourceId;

  /// The 64-bit id `mangas.source` stores for this extension.
  ///
  /// Mihon derives it as a folded MD5 of `"name.lowercase()/lang/versionId"`,
  /// which is what a Mihon backup's manga rows carry. Our extensions are keyed
  /// on disk by a readable slug instead, so a slug-derived id could never
  /// match one of those rows — every restored entry came out a stub. An
  /// extension now declares Mihon's number as `source_id` and that is the
  /// identity the app uses; the slug stays the on-disk/preferences key.
  ///
  /// Extensions that don't declare one fall back to the slug hash, which is
  /// what they were before, so an older installed extension keeps working
  /// until it's updated.
  int get sourceId => declaredSourceId ?? sourceNumericId(id);

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
      userAgent: manifest['user_agent'] as String?,
      // `__install_url` is a sidecar key we stamp into the persisted
      // manifest copy at install time. Not part of the JS-side manifest
      // contract — the underscore prefix is the marker.
      installUrl: manifest['__install_url'] as String?,
      // Written by extensions as a decimal string (the values exceed what a
      // JS number holds exactly), but tolerate a num for hand-written
      // manifests.
      declaredSourceId: switch (manifest['source_id']) {
        final String s => int.tryParse(s),
        final num n => n.toInt(),
        _ => null,
      },
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
    // Name, then id: two extensions can legitimately share a name (the same
    // site in two languages, or the same source from two repos), and this
    // list seeds the order of Browse, global search and the migrate picker,
    // so a tie left to Dart's unstable sort would move rows around between
    // rebuilds.
    result.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
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
  /// loaded the JS source once in a [JsRuntime] to validate it. When
  /// [installUrl] is non-null it's stamped into the persisted manifest copy
  /// under `__install_url` so future sessions can re-fetch the origin.
  Future<InstalledExtension> install({
    required Map<String, dynamic> manifest,
    required String sourceCode,
    String? installUrl,
  }) async {
    final id = manifest['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError('Manifest missing required `id` field');
    }
    // Copy so we don't mutate the caller's map; strip any stale
    // `__install_url` then stamp the new one (or leave absent when the
    // install has no remembered origin).
    final toWrite = Map<String, dynamic>.of(manifest)..remove('__install_url');
    if (installUrl != null && installUrl.isNotEmpty) {
      toWrite['__install_url'] = installUrl;
    }
    final dir = _dirFor(id);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _manifestFile(id).writeAsString(jsonEncode(toWrite));
    await _sourceFile(id).writeAsString(sourceCode);
    return InstalledExtension.fromManifest(toWrite, _sourceFile(id).path);
  }

  Future<void> uninstall(String id) async {
    final dir = _dirFor(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
