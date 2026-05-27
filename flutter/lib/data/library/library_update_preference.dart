import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-facing choice for how often the background library updater fires.
/// Matches the option list shown in Mihon's settings.
///
/// Values are persisted as `int` hours so the value itself is the recurrence
/// interval passed to workmanager. `0` means "manual only" — no scheduled
/// work.
enum LibraryUpdateInterval {
  manual(0, 'Manual only'),
  every12h(12, 'Every 12 hours'),
  daily(24, 'Daily'),
  every48h(48, 'Every 2 days'),
  weekly(168, 'Weekly');

  const LibraryUpdateInterval(this.hours, this.label);

  final int hours;
  final String label;

  static LibraryUpdateInterval fromHours(int hours) {
    for (final v in values) {
      if (v.hours == hours) return v;
    }
    return LibraryUpdateInterval.daily;
  }
}

class LibraryUpdatePreferenceNotifier
    extends Notifier<LibraryUpdateInterval> {
  // Key carefully chosen to be migration-friendly with the Kotlin app's
  // `pref_library_update_interval_key` once we wire up a migration step.
  static const _key = 'pref_library_update_interval_hours';

  @override
  LibraryUpdateInterval build() {
    _loadFromDisk();
    return LibraryUpdateInterval.daily;
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    if (stored == null) return;
    final loaded = LibraryUpdateInterval.fromHours(stored);
    if (loaded != state) state = loaded;
  }

  Future<void> setInterval(LibraryUpdateInterval interval) async {
    state = interval;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, interval.hours);
  }
}

final libraryUpdatePreferenceProvider =
    NotifierProvider<LibraryUpdatePreferenceNotifier, LibraryUpdateInterval>(
  LibraryUpdatePreferenceNotifier.new,
);
