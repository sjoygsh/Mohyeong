import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/source/model/manga_source.dart';
import '../network/app_http_client.dart';
import '../network/network_preferences.dart';
import 'installed_extension.dart';
import 'js/js_source.dart';
import 'local_source.dart';
import 'local_source_preferences.dart';
import 'source_icon.dart';
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

  /// In-flight loads by slug, so concurrent [getSource] calls share one
  /// [JsSource.load] instead of each spawning (and orphaning) a runtime.
  /// Removing an entry INVALIDATES that load: when it completes it disposes
  /// its runtime instead of caching it (see [getSource]).
  final Map<String, Future<MangaSource>> _loading = {};

  /// Set by [close]; loads that finish afterwards dispose themselves
  /// instead of repopulating the cleared cache (a background-isolate
  /// teardown racing an in-flight load leaked the runtime).
  bool _closed = false;
  final _changes = StreamController<List<InstalledExtension>>.broadcast();

  /// Stream of installed-extension lists. Emits on every install/uninstall;
  /// subscribers (the extensions tab) re-render off this.
  Stream<List<InstalledExtension>> watchInstalled() async* {
    yield await listInstalled();
    yield* _changes.stream;
  }

  /// Cached installed-extension list. Every call previously re-read and
  /// re-decoded every manifest.json on disk — and [_resolveSlug] runs on
  /// every [getSource], so numeric-id lookups of non-numeric slugs (the
  /// reader / details / downloader paths) paid that walk per fetch.
  /// Invalidated by [_emitChanges] on install/uninstall; a failed read is
  /// not cached. Consumers treat the shared list as read-only (they filter
  /// into copies).
  Future<List<InstalledExtension>>? _installedCache;

  Future<List<InstalledExtension>> listInstalled() {
    final cached = _installedCache;
    if (cached != null) return cached;
    late final Future<List<InstalledExtension>> future;
    future = () async {
      try {
        return await _storage.listInstalled();
      } catch (_) {
        if (_installedCache == future) _installedCache = null;
        rethrow;
      }
    }();
    return _installedCache = future;
  }

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
    if (_closed) throw StateError('ExtensionRepository is closed');
    final slug = await _resolveSlug(id);
    final cached = _loaded[slug];
    if (cached != null) return cached;
    // De-dupe concurrent first requests for one source: the download drain
    // runs several chapters of the same manga in parallel, and each spawned
    // load is a live worker isolate + QuickJS runtime — without this, every
    // caller but the last leaks one.
    final inflight = _loading[slug];
    if (inflight != null) return inflight;
    late final Future<MangaSource> future;
    future = () async {
      final src = await _loadSource(slug);
      // Invalidated mid-load (uninstall / version install / close removed
      // this future from [_loading]): caching [src] would resurrect a
      // runtime for code that no longer exists on disk — dispose it and
      // start over so the caller gets the CURRENT on-disk state (or a
      // clear read error when it was uninstalled).
      if (_loading[slug] != future) {
        await src.dispose();
        if (_closed) throw StateError('ExtensionRepository is closed');
        return getSource(slug);
      }
      _loaded[slug] = src;
      return src;
    }();
    _loading[slug] = future;
    try {
      return await future;
    } finally {
      if (_loading[slug] == future) _loading.remove(slug);
    }
  }

  Future<MangaSource> _loadSource(String slug) async {
    if (slug == LocalSource.sourceId) return LocalSource(_localPrefs);
    final source = await _storage.readSource(slug);
    final js = await JsSource.load(
      source,
      dio: _http.dio,
      // Surface extension `console.*` output to logcat in debug builds so
      // source authors can diagnose scrapers; silent in release.
      onLog: kDebugMode ? (level, msg) => debugPrint('[ext $slug] $msg') : null,
    );
    // Inject the user's per-source settings (optional `preferences()`
    // contract) so the extension sees its stored `__sourcePrefs` from the
    // first call.
    final stored = await getSourcePrefs(slug);
    if (stored.isNotEmpty) js.setSourcePrefs(stored);
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
  ///
  /// Memoised per requested id: this runs on EVERY [getSource], and the
  /// numeric-id form hashed every installed slug per call. The mapping only
  /// changes on install/uninstall, which clears the memo in [_emitChanges]
  /// (so a fallback recorded before an extension was installed re-resolves).
  final Map<String, String> _slugCache = {};
  int _slugCacheGen = 0;

  Future<String> _resolveSlug(String id) async {
    final hit = _slugCache[id];
    if (hit != null) return hit;
    final gen = _slugCacheGen;
    final resolved = await () async {
      if (id == LocalSource.sourceId) return id;
      if (_loaded.containsKey(id)) return id;
      final installed = await listInstalled();
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
    }();
    // Memoise only if no install/uninstall cleared the cache while this
    // resolution was in flight: it was computed from the OLD installed
    // list, and writing it back after the clear would pin a stale answer
    // (e.g. a numeric id's not-found fallback recorded just as that very
    // extension finished installing) until the next change event.
    if (gen == _slugCacheGen) _slugCache[id] = resolved;
    return resolved;
  }

  /// The installed-extension slug that owns [sourceId], or null when no
  /// installed extension hashes to it. Mirrors Mihon's
  /// `ExtensionManager.getExtensionPackage(sourceId)` — in the JS rewrite the
  /// slug stands in for the APK package name. Used to resolve per-extension
  /// incognito state.
  Future<String?> getExtensionPackage(int sourceId) async {
    final installed = await listInstalled();
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
    final installed = await listInstalled();
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
    // code. Also invalidate an in-flight load of the old code — letting it
    // finish would cache the stale version over the fresh install.
    final old = _loaded.remove(installed.id);
    await old?.dispose();
    _loading.remove(installed.id);
    sourcePrefsCapabilityCache.remove(installed.id);
    await _emitChanges();
    return installed;
  }

  Future<void> uninstall(String id) async {
    final loaded = _loaded.remove(id);
    await loaded?.dispose();
    // An in-flight load must not resurrect the uninstalled source.
    _loading.remove(id);
    sourcePrefsCapabilityCache.remove(id);
    // The favicon cache is keyed by source id and remembers MISSES as well as
    // hits, so without this a reinstall inherits whatever this id resolved to
    // — or failed to resolve to — last time, until that record's retry window
    // expires. Uninstall is the natural "forget this source" point, and it is
    // the repair a user reaches for when an icon is wrong.
    //
    // Deliberately NOT done on install/update: probing is flaky (many hosts
    // answer once and not the next run), so re-probing on every version bump
    // would trade a working icon for a coin flip.
    try {
      await SourceIconStore.instance.forget(id);
    } catch (_) {
      // Best effort — a stale icon must not abort an uninstall the user has
      // already committed to. The record expires on its own retry window.
    }
    await _storage.uninstall(id);
    await _emitChanges();
  }

  Future<void> _emitChanges() async {
    // The on-disk set just changed — drop the caches before re-reading so
    // the emission (and every later listInstalled / slug resolution)
    // reflects it. The generation bump keeps in-flight resolutions from
    // re-caching answers computed against the old list.
    _installedCache = null;
    _slugCacheGen++;
    _slugCache.clear();
    _changes.add(await listInstalled());
  }

  Future<void> close() async {
    _closed = true;
    // Invalidate in-flight loads; each disposes its own runtime on
    // completion instead of storing into the cleared map.
    _loading.clear();
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

/// Map of `int` source id → default image-request headers (Referer = the
/// source's base URL, plus the browser User-Agent), derived from the installed
/// extension list. Cover/thumbnail fetches go through the shared image cache,
/// which sends no source headers by default, so a CDN with hotlink protection
/// 403s and the cover renders blank — e.g. NatoManga's 2xstorage requires
/// `Referer: https://www.natomanga.com/`. Cover widgets look these up by
/// `manga.source` and pass them to [SourceImage]. A manifest `user_agent`
/// replaces the browser UA for hosts that reject it (MangaDex).
final installedSourceImageHeadersProvider =
    StreamProvider<Map<int, Map<String, String>>>((ref) async* {
  final repo = ref.watch(extensionRepositoryProvider);
  await for (final list in repo.watchInstalled()) {
    final m = <int, Map<String, String>>{};
    for (final e in list) {
      if (e.baseUrl.isEmpty) continue;
      final base = e.baseUrl.replaceAll(RegExp(r'/+$'), '');
      m[sourceNumericId(e.id)] = {
        'Referer': '$base/',
        'User-Agent': e.userAgent ?? defaultUserAgent,
      };
    }
    yield m;
  }
});
