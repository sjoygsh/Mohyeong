// ===========================================================================
// Tide more.
//
// The hub holds two different kinds of thing, and the old screen drew them
// identically: two global MODES that are on or off right now, and a list of
// DESTINATIONS that go somewhere. So the modes come first, as cards that light
// up when they are active — a mode you have forgotten you left on is the whole
// failure case here — and the destinations follow in named groups.
//
// Nothing separates the groups but their own labels. A divider says "these are
// different"; a label says what they are.
// ===========================================================================

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/base/base_preferences.dart';
import '../../data/download/download_repository.dart';
import '../../data/source/incognito_preferences.dart';
import '../about/about_screen.dart';
import '../dev/dev_page_source_screen.dart';
import '../categories/categories_screen.dart';
import '../downloads/download_queue_screen.dart';
import '../home/home_screen.dart';
import '../settings/data_storage_settings_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../tide/tide.dart';

/// "More" hub — equivalent to the Kotlin MoreScreen. Routes to Settings,
/// Categories, Data and storage, About, etc, and hosts the two global mode
/// toggles.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  /// Verbatim Kotlin `Constants.URL_HELP`.
  static const _urlHelp = 'https://sjoygsh.github.io/Mohyeong/help.html';

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Mirrors Kotlin MoreTab.onReselect: tapping the already-selected More
    // destination opens Settings. The index is 3, not 4 — this went dead when
    // the Updates tab was removed and every tab after it shifted down one.
    ref.listenManual<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab != 3 || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _push(Widget screen) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(homeTabIndexProvider) == 3;
    final downloadedOnly = ref.watch(downloadedOnlyProvider);
    final incognito = ref.watch(incognitoModeProvider);

    return TickerMode(
      enabled: visible,
      child: Scaffold(
        backgroundColor: TideColors.ground,
        body: Stack(
          children: [
            const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.page)),
            Positioned.fill(
              child: TideRise(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 14,
                    bottom: tideBarInset,
                  ),
                  children: [
                    // No logo slab. The app does not need to introduce itself
                    // on a settings hub any more than it did on the home feed;
                    // its identity lives on the About screen.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Text('More', style: TideText.display(32)),
                    ),
                    const TideSectionHeader(
                      label: 'Modes',
                      padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
                    ),
                    _group([
                      // Verbatim Mihon strings label_downloaded_only /
                      // _summary.
                      TideRow(
                        icon: Icons.cloud_off_outlined,
                        title: 'Downloaded only',
                        subtitle: 'Filters all entries in your library',
                        lit: downloadedOnly,
                        onTap: () => ref
                            .read(downloadedOnlyProvider.notifier)
                            .set(!downloadedOnly),
                        trailing: TideSwitch(
                          value: downloadedOnly,
                          onChanged:
                              ref.read(downloadedOnlyProvider.notifier).set,
                        ),
                      ),
                      // Verbatim Mihon strings pref_incognito_mode / _summary.
                      TideRow(
                        icon: Icons.no_encryption_gmailerrorred_outlined,
                        title: 'Incognito mode',
                        subtitle: 'Pauses reading history',
                        lit: incognito,
                        onTap: () => ref
                            .read(incognitoModeProvider.notifier)
                            .set(!incognito),
                        trailing: TideSwitch(
                          value: incognito,
                          onChanged: ref.read(incognitoModeProvider.notifier).set,
                        ),
                      ),
                    ]),
                    const TideSectionHeader(label: 'Library'),
                    TideTileGrid(
                      tiles: [
                        TideTile(
                          icon: Icons.get_app,
                          title: 'Download queue',
                          hint: 'In progress, paused',
                          // The one destination here with live state behind it:
                          // whether anything is downloading right now is worth
                          // knowing before you tap.
                          trailing: const _QueueCount(),
                          onTap: () => _push(const DownloadQueueScreen()),
                        ),
                        TideTile(
                          icon: Icons.label_outlined,
                          title: 'Categories',
                          hint: 'Shelves, sorting',
                          onTap: () => _push(const CategoriesScreen()),
                        ),
                        TideTile(
                          icon: Icons.query_stats,
                          title: 'Statistics',
                          hint: 'Time read, totals',
                          onTap: () => _push(const StatsScreen()),
                        ),
                      ],
                    ),
                    const TideSectionHeader(label: 'App'),
                    TideTileGrid(
                      tiles: [
                        TideTile(
                          icon: Icons.storage_outlined,
                          title: 'Data and storage',
                          hint: 'Backups, space',
                          onTap: () => _push(const DataStorageSettingsScreen()),
                        ),
                        TideTile(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          hint: 'Everything else',
                          onTap: () => _push(const SettingsScreen()),
                        ),
                        TideTile(
                          icon: Icons.info_outlined,
                          title: 'About',
                          hint: 'Version, links',
                          onTap: () => _push(const AboutScreen()),
                        ),
                        TideTile(
                          icon: Icons.help_outlined,
                          title: 'Help',
                          hint: 'Opens in browser',
                          trailing: Icon(
                            Icons.open_in_new,
                            size: 15,
                            color: TideColors.textAt(0.3),
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(MoreScreen._urlHelp),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                    // Developer tool for authoring source extensions: dumps a
                    // Cloudflare-cleared, JS-rendered page's DOM to a file for
                    // off-device inspection. It harvests live cookies, so it
                    // is compiled out of release builds rather than shipped.
                    if (kDebugMode) ...[
                      const TideSectionHeader(label: 'Developer'),
                      TideTileGrid(
                        tiles: [
                          TideTile(
                            icon: Icons.bug_report_outlined,
                            title: 'Dev: page source',
                            hint: 'Dump rendered DOM',
                            onTap: () => _push(const DevPageSourceScreen()),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rows sit apart rather than fused into one slab: each is its own pane of
  /// glass, which is what makes a lit one readable as lit.
  Widget _group(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            row,
          ],
        ],
      ),
    );
  }
}

/// Live count of everything queued or running, or a chevron when the queue is
/// empty. Structural download events are what change it, so it rides the
/// repository's own event stream rather than polling.
///
/// Resolved only while More is the visible tab. The shell pre-warms every tab
/// during post-launch idle, and touching the download repository builds the
/// whole download stack — a connectivity subscription and an HTTP client — to
/// render a number nobody is looking at. Off-tab it stays a plain chevron.
class _QueueCount extends ConsumerStatefulWidget {
  const _QueueCount();

  @override
  ConsumerState<_QueueCount> createState() => _QueueCountState();
}

class _QueueCountState extends ConsumerState<_QueueCount> {
  @override
  Widget build(BuildContext context) {
    if (ref.watch(homeTabIndexProvider) != 3) return const TideChevron();
    final repo = ref.watch(downloadRepositoryProvider);
    return StreamBuilder<DownloadEvent>(
      stream: repo.events,
      builder: (context, _) {
        final count = repo.snapshot().length;
        if (count == 0) return const TideChevron();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TideBadge('$count'),
            const SizedBox(width: 8),
            const TideChevron(),
          ],
        );
      },
    );
  }
}
