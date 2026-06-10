/// Chapter-row swipe actions, ported from Mihon's
/// `LibraryPreferences.swipeToStartAction` / `swipeToEndAction`.
library;

import '../preferences/typed_preferences.dart';

/// What a horizontal swipe on a chapter row does. Stored by Kotlin enum
/// name (`preferenceStore.getEnum` persists `name()`), kept verbatim for
/// settings-import parity.
enum ChapterSwipeAction {
  toggleRead('ToggleRead', 'Mark as read'),
  toggleBookmark('ToggleBookmark', 'Bookmark'),
  download('Download', 'Download'),
  disabled('Disabled', 'Disabled');

  const ChapterSwipeAction(this.storageName, this.label);

  /// The Kotlin enum constant name, as persisted.
  final String storageName;

  /// Verbatim Mihon label (action_mark_as_read / action_bookmark /
  /// action_download / disabled).
  final String label;

  static ChapterSwipeAction fromName(String? name) {
    for (final v in values) {
      if (v.storageName == name) return v;
    }
    return ChapterSwipeAction.disabled;
  }
}

/// Swipe toward the start (right-to-left in LTR). NOTE the pref KEYS are
/// crossed relative to the property names — Kotlin stores swipeToStart under
/// `pref_chapter_swipe_end_action` and vice versa; matched verbatim so a
/// settings import lands on the same behaviour.
final swipeToStartActionProvider = stringPref(
  'pref_chapter_swipe_end_action',
  'ToggleBookmark',
);

/// Swipe toward the end (left-to-right in LTR). Default: toggle read.
final swipeToEndActionProvider = stringPref(
  'pref_chapter_swipe_start_action',
  'ToggleRead',
);
