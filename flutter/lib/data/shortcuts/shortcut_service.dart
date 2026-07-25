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
  static const typeHistory = 'show_recently_read';
  static const typeBrowse = 'show_catalogues';

  // Home-tab indices (match HomeScreen's tab order). The recently-updated
  // shortcut is gone with the Updates tab: new chapters are on the home feed,
  // which is where the library shortcut already lands.
  static const _tabHome = 0;
  static const _tabHistory = 1;
  static const _tabBrowse = 2;

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
      ShortcutItem(type: typeLibrary, localizedTitle: 'Home'),
      ShortcutItem(type: typeHistory, localizedTitle: 'History'),
      ShortcutItem(type: typeBrowse, localizedTitle: 'Browse'),
    ]);
  }

  int? _tabIndexFor(String type) {
    switch (type) {
      case typeLibrary:
        return _tabHome;
      case typeHistory:
        return _tabHistory;
      case typeBrowse:
        return _tabBrowse;
    }
    return null;
  }
}
