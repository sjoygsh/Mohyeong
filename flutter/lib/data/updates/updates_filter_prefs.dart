import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/manga/model/tri_state.dart';

/// Persisted set of filters applied to the Updates tab. Mirrors the
/// subset of Mihon's `UpdatesFilterScreen` that is meaningful given our
/// `LibraryUpdate` projection: read/bookmark tri-states plus a flip for
/// hiding rows belonging to a muted scanlator.
///
/// The downloaded-state axis is intentionally absent — it would require
/// a filesystem probe per row and the Updates list can be large.
class UpdatesFilters {
  const UpdatesFilters({
    this.unread = TriState.disabled,
    this.bookmark = TriState.disabled,
    this.hideMutedScanlators = false,
  });

  /// Tri-state over `LibraryUpdate.read` — include rows where the
  /// chapter is unread / read / both.
  final TriState unread;

  /// Tri-state over `LibraryUpdate.bookmark`.
  final TriState bookmark;

  /// When true, rows where the scanlator is in the per-manga excluded
  /// set are dropped entirely. When false (default), they still appear
  /// with strikethrough — Mihon's default behaviour.
  final bool hideMutedScanlators;

  bool get isActive =>
      unread != TriState.disabled ||
      bookmark != TriState.disabled ||
      hideMutedScanlators;

  UpdatesFilters copyWith({
    TriState? unread,
    TriState? bookmark,
    bool? hideMutedScanlators,
  }) {
    return UpdatesFilters(
      unread: unread ?? this.unread,
      bookmark: bookmark ?? this.bookmark,
      hideMutedScanlators: hideMutedScanlators ?? this.hideMutedScanlators,
    );
  }
}

/// SharedPreferences-backed Notifier for the Updates filter set. Each
/// tri-state is encoded as an int in `{0,1,2}` so the on-disk form
/// stays round-trippable across versions; the boolean rides as a `bool`.
class UpdatesFiltersNotifier extends Notifier<UpdatesFilters> {
  static const _kUnread = 'pref_updates_filter_unread';
  static const _kBookmark = 'pref_updates_filter_bookmark';
  static const _kHideMuted = 'pref_updates_hide_muted_scanlators';

  @override
  UpdatesFilters build() {
    _loadFromDisk();
    return const UpdatesFilters();
  }

  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final next = UpdatesFilters(
      unread: _decodeTri(prefs.getInt(_kUnread)),
      bookmark: _decodeTri(prefs.getInt(_kBookmark)),
      hideMutedScanlators: prefs.getBool(_kHideMuted) ?? false,
    );
    if (next.unread != state.unread ||
        next.bookmark != state.bookmark ||
        next.hideMutedScanlators != state.hideMutedScanlators) {
      state = next;
    }
  }

  Future<void> setUnread(TriState v) async => _persist(state.copyWith(unread: v));
  Future<void> setBookmark(TriState v) async =>
      _persist(state.copyWith(bookmark: v));
  Future<void> setHideMutedScanlators(bool v) async =>
      _persist(state.copyWith(hideMutedScanlators: v));

  Future<void> _persist(UpdatesFilters next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUnread, next.unread.index);
    await prefs.setInt(_kBookmark, next.bookmark.index);
    await prefs.setBool(_kHideMuted, next.hideMutedScanlators);
  }

  static TriState _decodeTri(int? v) {
    switch (v) {
      case 1:
        return TriState.enabledIs;
      case 2:
        return TriState.enabledNot;
      default:
        return TriState.disabled;
    }
  }
}

final updatesFiltersProvider =
    NotifierProvider<UpdatesFiltersNotifier, UpdatesFilters>(
  UpdatesFiltersNotifier.new,
);
