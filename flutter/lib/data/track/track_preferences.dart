import '../preferences/typed_preferences.dart';

/// Tracking preferences mirroring Kotlin `TrackPreferences`. Keys match the
/// Kotlin app verbatim so a settings import carries values across untranslated.

/// Push chapter progress to bound trackers automatically after a chapter is
/// read in the reader. Kotlin key `pref_auto_update_manga_sync_key`,
/// default true.
final autoUpdateTrackProvider =
    boolPref('pref_auto_update_manga_sync_key', true);

/// Report the parsed volume number to trackers instead of the chapter number,
/// when known. Kotlin key `pref_track_by_volume`, default false.
final trackByVolumeProvider = boolPref('pref_track_by_volume', false);

/// Whether marking chapters read from the manga screen pushes progress to
/// trackers. Mirrors Kotlin `AutoTrackState`; the [key] is the persisted enum
/// name (matching Kotlin `getEnum`) and the [label] its settings string.
enum AutoTrackState {
  always('ALWAYS', 'Always'),
  ask('ASK', 'Always ask'),
  never('NEVER', 'Never');

  const AutoTrackState(this.key, this.label);

  final String key;
  final String label;

  static AutoTrackState fromKey(String key) =>
      values.firstWhere((s) => s.key == key, orElse: () => always);
}

/// Kotlin key `pref_auto_update_manga_on_mark_read`, default ALWAYS. Stored as
/// the enum name.
final autoUpdateTrackOnMarkReadProvider =
    stringPref('pref_auto_update_manga_on_mark_read', AutoTrackState.always.key);
