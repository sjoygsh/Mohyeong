import 'package:quick_actions/quick_actions.dart';

/// Launcher app-shortcuts (the home-screen long-press menu), ported from the
/// Kotlin app's `shortcuts.xml` + `MainActivity.handleIntentAction`. Each
/// shortcut jumps straight to one of the top-level home tabs.
///
/// The shortcut [type] strings are Mihon's verbatim `shortcutId` values so the
/// behaviour (and any external launcher integrations) matches the Kotlin app.
///
/// Plain singleton (no Riverpod) so it can be wired from app start; the tab
/// dispatch is handed back to the caller via the [init] callback.
class ShortcutService {
  ShortcutService._();

  static final ShortcutService instance = ShortcutService._();

  // Verbatim Mihon shortcut ids (see shortcuts.xml).
  static const typeLibrary = 'show_library';
  static const typeUpdates = 'show_recently_updated';
  static const typeHistory = 'show_recently_read';
  static const typeBrowse = 'show_catalogues';

  // Home-tab indices (match HomeScreen's tab order).
  static const _tabLibrary = 0;
  static const _tabUpdates = 1;
  static const _tabHistory = 2;
  static const _tabBrowse = 3;

  final QuickActions _quickActions = const QuickActions();

  /// Registers the launcher shortcuts and wires [onSelectTab] to fire with the
  /// target home-tab index when the user launches one. Call once at startup;
  /// [onSelectTab] also fires for the cold-start shortcut that launched the app.
  Future<void> init(void Function(int tabIndex) onSelectTab) async {
    _quickActions.initialize((type) {
      final index = _tabIndexFor(type);
      if (index != null) onSelectTab(index);
    });
    await _quickActions.setShortcutItems(const [
      ShortcutItem(type: typeLibrary, localizedTitle: 'Library'),
      ShortcutItem(type: typeUpdates, localizedTitle: 'Updates'),
      ShortcutItem(type: typeHistory, localizedTitle: 'History'),
      ShortcutItem(type: typeBrowse, localizedTitle: 'Browse'),
    ]);
  }

  int? _tabIndexFor(String type) {
    switch (type) {
      case typeLibrary:
        return _tabLibrary;
      case typeUpdates:
        return _tabUpdates;
      case typeHistory:
        return _tabHistory;
      case typeBrowse:
        return _tabBrowse;
    }
    return null;
  }
}
