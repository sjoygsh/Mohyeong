import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps the two source-visibility prefs Mihon uses to hide noise on
/// the Sources/Browse list:
///
///  * `source_languages` — set of enabled language codes. Sources whose
///    `lang` isn't in this set get hidden (and the per-source toggle
///    isn't even shown). Default: `{en}` (Mihon picks based on system
///    locale; we keep it simple — the user can flip on more from the
///    filter screen).
///  * `hidden_catalogues` — set of source id strings the user has
///    explicitly silenced even though their language is enabled.
///
/// Keys + on-disk shape match Mihon for backup interop (Mihon writes a
/// `Set<String>` via Android SharedPreferences; the `shared_preferences`
/// plugin reads/writes that as a `List<String>` on Android).
class SourcePreferences {
  SourcePreferences(this._prefs);

  static const String keyEnabledLanguages = 'source_languages';
  static const String keyDisabledSources = 'hidden_catalogues';
  static const String keyPinnedSources = 'pinned_catalogues';

  // Migration source selection + smart-search tuning. Keys + shapes match
  // Mihon so a settings backup round-trips. `migration_sources` is stored
  // exactly as Mihon's `getLongArray` does — a single comma-joined string
  // value, not a string list.
  static const String keyMigrationSources = 'migration_sources';
  static const String keyMigrationDeepSearch = 'migration_deep_search';
  static const String keyMigrationPrioritizeByChapters =
      'migration_prioritize_by_chapters';
  static const String keyMigrationHideUnmatched = 'migration_hide_unmatched';
  static const String keyMigrationHideWithoutUpdates =
      'migration_hide_without_updates';

  final SharedPreferences _prefs;

  final StreamController<Set<String>> _enabledLangs =
      StreamController<Set<String>>.broadcast();
  final StreamController<Set<String>> _disabledSrcs =
      StreamController<Set<String>>.broadcast();
  final StreamController<Set<String>> _pinnedSrcs =
      StreamController<Set<String>>.broadcast();

  Set<String> getEnabledLanguages() {
    final raw = _prefs.getStringList(keyEnabledLanguages);
    if (raw == null) return const {'en'};
    return raw.toSet();
  }

  Set<String> getDisabledSources() {
    final raw = _prefs.getStringList(keyDisabledSources);
    if (raw == null) return const <String>{};
    return raw.toSet();
  }

  Set<String> getPinnedSources() {
    final raw = _prefs.getStringList(keyPinnedSources);
    if (raw == null) return const <String>{};
    return raw.toSet();
  }

  Stream<Set<String>> watchEnabledLanguages() async* {
    yield getEnabledLanguages();
    yield* _enabledLangs.stream;
  }

  Stream<Set<String>> watchDisabledSources() async* {
    yield getDisabledSources();
    yield* _disabledSrcs.stream;
  }

  Stream<Set<String>> watchPinnedSources() async* {
    yield getPinnedSources();
    yield* _pinnedSrcs.stream;
  }

  Future<void> setEnabledLanguages(Set<String> langs) async {
    await _prefs.setStringList(keyEnabledLanguages, langs.toList()..sort());
    _enabledLangs.add(getEnabledLanguages());
  }

  Future<void> setDisabledSources(Set<String> ids) async {
    await _prefs.setStringList(keyDisabledSources, ids.toList()..sort());
    _disabledSrcs.add(getDisabledSources());
  }

  Future<void> setPinnedSources(Set<String> ids) async {
    await _prefs.setStringList(keyPinnedSources, ids.toList()..sort());
    _pinnedSrcs.add(getPinnedSources());
  }

  Future<void> toggleSourcePin(String id) async {
    final current = getPinnedSources();
    final next = current.contains(id)
        ? (current.toSet()..remove(id))
        : (current.toSet()..add(id));
    await setPinnedSources(next);
  }

  Future<void> toggleLanguage(String code) async {
    final current = getEnabledLanguages();
    final next = current.contains(code)
        ? (current.toSet()..remove(code))
        : (current.toSet()..add(code));
    await setEnabledLanguages(next);
  }

  /// The ordered set of source ids the user last chose on the migration
  /// config screen. Empty when never configured (callers then fall back to
  /// pinned / non-disabled, mirroring Mihon's `initSources`).
  List<int> getMigrationSources() {
    final raw = _prefs.getString(keyMigrationSources);
    if (raw == null || raw.isEmpty) return const <int>[];
    return raw.split(',').map(int.tryParse).whereType<int>().toList();
  }

  Future<void> setMigrationSources(List<int> ids) async {
    await _prefs.setString(keyMigrationSources, ids.join(','));
  }

  bool getMigrationDeepSearch() =>
      _prefs.getBool(keyMigrationDeepSearch) ?? false;

  Future<void> setMigrationDeepSearch(bool value) async {
    await _prefs.setBool(keyMigrationDeepSearch, value);
  }

  bool getMigrationPrioritizeByChapters() =>
      _prefs.getBool(keyMigrationPrioritizeByChapters) ?? false;

  Future<void> setMigrationPrioritizeByChapters(bool value) async {
    await _prefs.setBool(keyMigrationPrioritizeByChapters, value);
  }

  bool getMigrationHideUnmatched() =>
      _prefs.getBool(keyMigrationHideUnmatched) ?? false;

  Future<void> setMigrationHideUnmatched(bool value) async {
    await _prefs.setBool(keyMigrationHideUnmatched, value);
  }

  bool getMigrationHideWithoutUpdates() =>
      _prefs.getBool(keyMigrationHideWithoutUpdates) ?? false;

  Future<void> setMigrationHideWithoutUpdates(bool value) async {
    await _prefs.setBool(keyMigrationHideWithoutUpdates, value);
  }

  Future<void> toggleSource(String id) async {
    final current = getDisabledSources();
    // Mihon stores DISABLED ids — toggling "enables" by removing, or
    // "disables" by adding.
    final next = current.contains(id)
        ? (current.toSet()..remove(id))
        : (current.toSet()..add(id));
    await setDisabledSources(next);
  }
}

final sourcePreferencesProvider =
    FutureProvider<SourcePreferences>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SourcePreferences(prefs);
});
