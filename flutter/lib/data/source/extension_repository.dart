import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/source/model/manga_source.dart';
import '../network/app_http_client.dart';
import 'installed_extension.dart';
import 'js/js_source.dart';
import 'local_source.dart';
import 'local_source_preferences.dart';

/// In-memory cache of loaded [MangaSource] instances plus the install /
/// uninstall surface used by the browse / extensions UI.
///
/// Distinct from the persisted `SourceRepository` in
/// `source_repository.dart`: that one writes Mihon's `sources` table (the
/// small id/lang/name row written when a manga is saved). This one manages
/// the *live* JS-backed sources you call to fetch popular/search/etc.
///
/// Sources are lazily loaded: a JS runtime is only spun up the first time
/// the user opens a given source. Uninstalling disposes the runtime and
/// deletes the on-disk files.
class ExtensionRepository {
  ExtensionRepository(this._storage, this._http, this._localPrefs);

  final ExtensionStorage _storage;
  final AppHttpClient _http;
  final LocalSourcePreferences _localPrefs;
  final Map<String, MangaSource> _loaded = {};
  final _changes = StreamController<List<InstalledExtension>>.broadcast();

  /// Stream of installed-extension lists. Emits on every install/uninstall;
  /// subscribers (the extensions tab) re-render off this.
  Stream<List<InstalledExtension>> watchInstalled() async* {
    yield await _storage.listInstalled();
    yield* _changes.stream;
  }

  Future<List<InstalledExtension>> listInstalled() => _storage.listInstalled();

  /// Returns a loaded [MangaSource], spinning up its JS runtime the first
  /// time it's requested. Source id `'0'` is the built-in Local source,
  /// served from the filesystem rather than the JS extension store.
  Future<MangaSource> getSource(String id) async {
    final cached = _loaded[id];
    if (cached != null) return cached;
    if (id == LocalSource.sourceId) {
      final local = LocalSource(_localPrefs);
      _loaded[id] = local;
      return local;
    }
    final source = await _storage.readSource(id);
    final js = await JsSource.load(source, dio: _http.dio);
    _loaded[id] = js;
    return js;
  }

  /// Installs from a local JS file. The file is validated by loading it
  /// once in a throwaway runtime to read the manifest before persisting.
  Future<InstalledExtension> installFromFile(File file) async {
    final code = await file.readAsString();
    return installFromString(code);
  }

  /// Installs from a remote URL (raw .js file).
  Future<InstalledExtension> installFromUrl(String url) async {
    final response = await _http.dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final code = response.data;
    if (code == null || code.isEmpty) {
      throw StateError('Empty response from $url');
    }
    return installFromString(code);
  }

  Future<InstalledExtension> installFromString(String code) async {
    // Load once just to read + validate the manifest. The runtime gets
    // disposed; the real runtime spins up on first use.
    final probe = await JsSource.load(code, dio: _http.dio);
    final manifest = probe.manifest;
    await probe.dispose();
    final installed = await _storage.install(
      manifest: manifest,
      sourceCode: code,
    );
    // Drop any cached old version so the next getSource picks up the new
    // code.
    final old = _loaded.remove(installed.id);
    await old?.dispose();
    await _emitChanges();
    return installed;
  }

  Future<void> uninstall(String id) async {
    final loaded = _loaded.remove(id);
    await loaded?.dispose();
    await _storage.uninstall(id);
    await _emitChanges();
  }

  Future<void> _emitChanges() async {
    _changes.add(await _storage.listInstalled());
  }

  Future<void> close() async {
    for (final s in _loaded.values) {
      await s.dispose();
    }
    _loaded.clear();
    await _changes.close();
  }
}

final extensionRepositoryProvider = Provider<ExtensionRepository>((ref) {
  throw UnimplementedError(
    'ExtensionRepository must be overridden in main() once ExtensionStorage '
    'has been initialised.',
  );
});
