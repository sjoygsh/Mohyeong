import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reusable SharedPreferences-backed [Notifier]s for the large family of
/// simple scalar preferences Mihon exposes (bool toggles, int sliders,
/// string pickers). Each notifier takes its key + default through the
/// constructor so a single class covers every pref of that type — the
/// provider is built with a closure, e.g.:
///
/// ```dart
/// final fullscreenProvider = boolPref('pref_fullscreen', true);
/// ```
///
/// Keys deliberately mirror the Kotlin app's preference keys so a future
/// settings-import path carries values across without translation.
class BoolPrefNotifier extends Notifier<bool> {
  BoolPrefNotifier(this.key, this.defaultValue, {this.alsoRead = const []});

  final String key;
  final bool defaultValue;

  /// Older spellings of [key], read (in order) when [key] itself holds
  /// nothing, and dropped as soon as a value is written under [key].
  ///
  /// Preference keys are an on-disk contract shared with the Kotlin app: the
  /// v0.19 -> v1.0 upgrade happens in place under the same applicationId, and
  /// backups replay entries by key. So a key that was written down wrong is
  /// not a rename — it is a value the user set and the app then stopped
  /// reading.
  final List<String> alsoRead;

  @override
  bool build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var stored = prefs.getBool(key);
    for (final legacy in alsoRead) {
      if (stored != null) break;
      stored = prefs.getBool(legacy);
    }
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    for (final legacy in alsoRead) {
      await prefs.remove(legacy);
    }
  }
}

NotifierProvider<BoolPrefNotifier, bool> boolPref(
  String key,
  bool defaultValue, {
  List<String> alsoRead = const [],
}) =>
    NotifierProvider<BoolPrefNotifier, bool>(
      () => BoolPrefNotifier(key, defaultValue, alsoRead: alsoRead),
    );

class IntPrefNotifier extends Notifier<int> {
  IntPrefNotifier(this.key, this.defaultValue);

  final String key;
  final int defaultValue;

  @override
  int build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(key);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(int value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }
}

NotifierProvider<IntPrefNotifier, int> intPref(
  String key,
  int defaultValue,
) =>
    NotifierProvider<IntPrefNotifier, int>(
      () => IntPrefNotifier(key, defaultValue),
    );

class StringPrefNotifier extends Notifier<String> {
  StringPrefNotifier(this.key, this.defaultValue);

  final String key;
  final String defaultValue;

  @override
  String build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }
}

NotifierProvider<StringPrefNotifier, String> stringPref(
  String key,
  String defaultValue,
) =>
    NotifierProvider<StringPrefNotifier, String>(
      () => StringPrefNotifier(key, defaultValue),
    );

/// String-set preference, persisted via SharedPreferences' string-list
/// store (Flutter has no native set type). Mihon stores these as a
/// `StringSet`; we mirror the key and treat order as insignificant.
class StringSetPrefNotifier extends Notifier<Set<String>> {
  StringSetPrefNotifier(this.key, this.defaultValue);

  final String key;
  final Set<String> defaultValue;

  @override
  Set<String> build() {
    _load();
    return defaultValue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(key);
    if (stored == null) return;
    final set = stored.toSet();
    if (set.length != state.length || !state.containsAll(set)) state = set;
  }

  Future<void> set(Set<String> value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value.toList());
  }
}

NotifierProvider<StringSetPrefNotifier, Set<String>> stringSetPref(
  String key,
  Set<String> defaultValue,
) =>
    NotifierProvider<StringSetPrefNotifier, Set<String>>(
      () => StringSetPrefNotifier(key, defaultValue),
    );
