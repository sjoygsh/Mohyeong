import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/source/model/manga_source.dart';
import '../network/app_http_client.dart';
import 'installed_extension.dart';
import 'js/js_source.dart';
import 'local_source.dart';
import 'local_source_preferences.dart';
import 'source_id.dart';

/// Session cache: extension id → declares the optional `preferences()`
/// contract (gates the per-source settings gear). Probing boots the
/// extension's JS runtime, so each id is probed at most once per run.
/// Lives here (not in the UI) so install/uninstall can evict the stale
/// entry — a reinstalled version that gains or drops `preferences()` would
/// otherwise keep its old gear visibility until app restart.
final Map<String, bool> sourcePrefsCapabilityCache = {};

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
  ///
  /// Callers pass either the extension's on-disk slug (browse / search /
  /// migration, where the source object's id is known) or the numeric
  /// `mangas.source` value (`manga.source.toString()` from reader /
  /// details / updater / downloader). For numeric-string slugs the two
  /// coincide; for non-numeric slugs the numeric form is the hashed id, so
  /// when a direct lookup misses we resolve the numeric id back to its slug
  /// via [sourceNumericId].
  Future<MangaSource> getSource(String id) async {
    final slug = await _resolveSlug(id);
    final cached = _loaded[slug];
    if (cached != null) return cached;
    if (slug == LocalSource.sourceId) {
      final local = LocalSource(_localPrefs);
      _loaded[slug] = local;
      return local;
    }
    final source = await _storage.readSource(slug);
    final js = await JsSource.load(source, dio: _http.dio);
    // Inject the user's per-source settings (optional `preferences()`
    // contract) so the extension sees its stored `__sourcePrefs` from the
    // first call.
    final stored = await getSourcePrefs(slug);
    if (stored.isNotEmpty) js.setSourcePrefs(stored);
    _loaded[slug] = js;
    return js;
  }

  /// SharedPreferences key for [slug]'s per-source settings — a JSON map of
  /// only the user's NON-default picks. Mirrors Kotlin's per-source
  /// preference stores (ConfigurableSource); carried in backups as
  /// `backupSourcePreferences` keyed by this slug.
  static String sourcePrefsKey(String slug) => 'source_prefs_$slug';

  Future<Map<String, String>> getSourcePrefs(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(sourcePrefsKey(slug));
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return const {};
    }
  }

  /// Persists [values] and re-injects them into the live runtime (when the
  /// source is loaded) so changes apply without an app restart.
  Future<void> setSourcePrefs(String slug, Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    if (values.isEmpty) {
      await prefs.remove(sourcePrefsKey(slug));
    } else {
      await prefs.setString(sourcePrefsKey(slug), jsonEncode(values));
    }
    final loaded = _loaded[slug];
    if (loaded is JsSource) loaded.setSourcePrefs(values);
  }

  /// Maps an incoming source id to the on-disk extension slug. A slug that
  /// names an installed extension (or the Local source) is returned as-is;
  /// otherwise, if the id is a numeric source id, we find the installed
  /// extension whose slug hashes to it. Falls back to the original id when
  /// nothing matches (the subsequent readSource surfaces a clear error).
  Future<String> _resolveSlug(String id) async {
    if (id == LocalSource.sourceId) return id;
    if (_loaded.containsKey(id)) return id;
    final installed = await _storage.listInstalled();
    for (final e in installed) {
      if (e.id == id) return id;
    }
    final numeric = int.tryParse(id);
    if (numeric != null) {
      for (final e in installed) {
        if (sourceNumericId(e.id) == numeric) return e.id;
      }
    }
    return id;
  }

  /// The installed-extension slug that owns [sourceId], or null when no
  /// installed extension hashes to it. Mirrors Mihon's
  /// `ExtensionManager.getExtensionPackage(sourceId)` — in the JS rewrite the
  /// slug stands in for the APK package name. Used to resolve per-extension
  /// incognito state.
  Future<String?> getExtensionPackage(int sourceId) async {
    final installed = await _storage.listInstalled();
    for (final e in installed) {
      if (sourceNumericId(e.id) == sourceId) return e.id;
    }
    return null;
  }

  /// Installs from a local JS file. The file is validated by loading it
  /// once in a throwaway runtime to read the manifest before persisting.
  Future<InstalledExtension> installFromFile(File file) async {
    final code = await file.readAsString();
    return installFromString(code);
  }

  /// Installs from a remote URL (raw .js file). The URL is remembered
  /// alongside the manifest so the Extensions tab can offer a one-tap
  /// update via [updateFromOrigin].
  Future<InstalledExtension> installFromUrl(String url) async {
    final response = await _http.dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final code = response.data;
    if (code == null || code.isEmpty) {
      throw StateError('Empty response from $url');
    }
    return installFromString(code, installUrl: url);
  }

  /// Checks every URL-installed extension's origin for a newer
  /// `version_code` (Kotlin's ExtensionUpdateJob equivalent for the JS
  /// model — there's no repo index, so the origin .js itself is the source
  /// of truth). Returns the ids with an update available; probe failures
  /// (offline, dead URL) are skipped so one bad origin doesn't poison the
  /// whole check.
  Future<Set<String>> checkForUpdates() async {
    final installed = await _storage.listInstalled();
    final updatable = <String>{};
    for (final e in installed) {
      final url = e.installUrl;
      if (url == null || url.isEmpty) continue;
      try {
        final response = await _http.dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final code = response.data;
        if (code == null || code.isEmpty) continue;
        // Cheap path: read version_code straight out of the manifest text
        // instead of booting a whole QuickJS runtime per extension on the
        // UI thread just to ask one number. Falls back to a runtime probe
        // for exotic formatting.
        var remoteVersion = _parseVersionCode(code);
        if (remoteVersion == null) {
          final probe = await JsSource.load(code, dio: _http.dio);
          remoteVersion = probe.versionCode;
          await probe.dispose();
        }
        if (remoteVersion > e.versionCode) updatable.add(e.id);
      } catch (_) {
        // Unreachable origin — not an update.
      }
    }
    return updatable;
  }

  /// Textual `version_code: N` scrape from an extension's manifest —
  /// enough for the update check without evaluating the JS.
  static int? _parseVersionCode(String code) {
    final m =
        RegExp('version_code[\'"]?\\s*:\\s*(\\d+)').firstMatch(code);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Re-runs the URL install for an extension that was previously
  /// installed from a URL. Throws when the extension has no remembered
  /// origin (it was installed from a local file).
  Future<InstalledExtension> updateFromOrigin(InstalledExtension e) {
    final url = e.installUrl;
    if (url == null || url.isEmpty) {
      throw StateError(
        'Extension ${e.name} has no remembered install URL — '
        'install from URL once first.',
      );
    }
    return installFromUrl(url);
  }

  Future<InstalledExtension> installFromString(
    String code, {
    String? installUrl,
  }) async {
    // Load once just to read + validate the manifest. The runtime gets
    // disposed; the real runtime spins up on first use.
    final probe = await JsSource.load(code, dio: _http.dio);
    final manifest = probe.manifest;
    await probe.dispose();
    final installed = await _storage.install(
      manifest: manifest,
      sourceCode: code,
      installUrl: installUrl,
    );
    // Drop any cached old version so the next getSource picks up the new
    // code.
    final old = _loaded.remove(installed.id);
    await old?.dispose();
    sourcePrefsCapabilityCache.remove(installed.id);
    await _emitChanges();
    return installed;
  }

  Future<void> uninstall(String id) async {
    final loaded = _loaded.remove(id);
    await loaded?.dispose();
    sourcePrefsCapabilityCache.remove(id);
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

/// Map of `int` source id → language code, derived from the installed
/// extension list. Mihon stores `Manga.source` as a 64-bit int but the
/// extension manifest ids are strings; we parse on the way in. Used by
/// the library language badge — looking it up per card via a stream
/// keeps the badge reactive when the user installs/uninstalls
/// extensions, without each card re-walking the manifest directory.
///
/// LocalSource (`'0'`) is intentionally absent from the map: it has no
/// meaningful language ('all'), so the language badge won't render on
/// local-source cards.
final installedSourceLangsProvider =
    StreamProvider<Map<int, String>>((ref) async* {
  final repo = ref.watch(extensionRepositoryProvider);
  await for (final list in repo.watchInstalled()) {
    final m = <int, String>{};
    for (final e in list) {
      m[sourceNumericId(e.id)] = e.lang;
    }
    yield m;
  }
});
