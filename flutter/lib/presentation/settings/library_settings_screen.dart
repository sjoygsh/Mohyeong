import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/chapter_swipe_preferences.dart';
import '../../data/library/library_display_prefs.dart';
import '../../data/library/library_update_preference.dart';
import '../../data/preferences/typed_preferences.dart';
import '../../domain/category/model/category.dart';
import '../categories/categories_screen.dart';
import 'category_filter_tile.dart';
import 'pref_tiles.dart';

/// Settings → Library. Mirror of Mihon's `SettingsLibraryScreen`, grouped
/// into Categories / Global update / Behavior, plus a Mohyeong-specific
/// Display/Badges section.
///
/// Wired 1:1 with Kotlin where the backing subsystem exists: the update
/// interval drives the workmanager schedule, the device restrictions
/// ([libraryUpdateDeviceRestrictionProvider]) feed the task's `Constraints`,
/// the tri-state categories scope the sweep, "Automatically refresh metadata"
/// ([autoUpdateMetadataProvider]) makes the sweep also pull manga details, and
/// smart-update + hide-missing + group-by-volume hook their respective paths.
///
/// Intentional differences from Kotlin's screen:
///   * Per-category "categorized display settings" aren't implemented, so
///     that Kotlin item is omitted rather than shipped as a dead switch.
///   * The keep-downloaded-removed item is omitted for the same reason —
///     its subsystem doesn't exist yet.
///   * Kotlin's "Show unread count on Updates icon"
///     (`pref_library_update_show_tab_badge`) is gone: it badged the Updates
///     tab, and this build folded Updates into the home feed's Tonight
///     section and deleted both the tab and the nav bar it sat in. With no
///     icon to badge it could only have been a dead switch.
///   * The Display/Badges section is a Mohyeong addition: the Flutter build
///     has no separate library display bottom-sheet, so these live here.
class LibrarySettingsScreen extends ConsumerWidget {
  const LibrarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(libraryUpdatePreferenceProvider);
    final intervalNotifier =
        ref.read(libraryUpdatePreferenceProvider.notifier);
    final categoryCount =
        ref.watch(userCategoriesProvider).valueOrNull?.length ?? 0;
    final showUnreadBadge = ref.watch(displayUnreadBadgeProvider);
    final showDownloadBadge = ref.watch(displayDownloadBadgeProvider);
    final showLocalBadge = ref.watch(displayLocalBadgeProvider);
    final showLanguageBadge = ref.watch(displayLanguageBadgeProvider);
    final showContinueReading = ref.watch(showContinueReadingButtonProvider);
    return PrefScaffold(
      title: 'Library',
      actions: [const PrefHelp('library')],
      children: [
          // ── Categories ──────────────────────────────────────────────
          const PrefSectionHeader('Categories'),
          PrefRow(
            title: 'Edit categories',
            subtitle: categoryCount == 1 ? '1 category' : '$categoryCount categories',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoriesScreen(),
              ),
            ),
          ),
          const _DefaultCategoryTile(),

          // ── Global update ───────────────────────────────────────────
          const PrefSectionHeader('Global update'),
          PrefRow(
            title: 'Automatic updates',
            subtitle: interval.label,
            onTap: () async {
              final picked = await pickPref<LibraryUpdateInterval>(
                context,
                title: 'Automatic updates',
                selected: interval,
                options: [
                  for (final v in LibraryUpdateInterval.values) (v, v.label),
                ],
              );
              if (picked != null) {
                await intervalNotifier.setInterval(picked);
              }
            },
          ),
          _DeviceRestrictionSection(
            enabled: interval != LibraryUpdateInterval.manual,
          ),
          CategoryTriStateTile(
            title: 'Categories',
            message: 'Entries in excluded categories will not be updated even '
                'if they are also in included categories.',
            includedProvider: libraryUpdateCategoriesProvider,
            excludedProvider: libraryUpdateCategoriesExcludeProvider,
          ),
          PrefSwitch(
            title: 'Automatically refresh metadata',
            subtitle: 'Check for new cover and details when updating library',
            provider: autoUpdateMetadataProvider,
          ),
          const _SmartUpdateSection(),

          // ── Behavior ────────────────────────────────────────────────
          const PrefSectionHeader('Behavior'),
          // Verbatim Mihon string pref_hide_missing_chapter_indicators.
          PrefSwitchRaw(
            title: 'Hide missing chapter indicators',
            subtitle: 'Hide the "Missing N chapters" rows between chapters with a '
              'numbering gap on the manga page',
            value: ref.watch(hideMissingChaptersProvider),
            onChanged: ref.read(hideMissingChaptersProvider.notifier).setEnabled,
          ),
          // Verbatim Mihon strings pref_group_chapters_by_volume / _summary.
          PrefSwitchRaw(
            title: 'Group chapters by volume',
            subtitle: 'Show volume headers between chapter groups on the manga page',
            value: ref.watch(groupChaptersByVolumeProvider),
            onChanged: ref.read(groupChaptersByVolumeProvider.notifier).setEnabled,
          ),
          // Verbatim Mihon strings pref_chapter_swipe_start / _end.
          _SwipeActionTile(
            title: 'Chapter on swipe to left',
            provider: swipeToStartActionProvider,
          ),
          _SwipeActionTile(
            title: 'Chapter on swipe to right',
            provider: swipeToEndActionProvider,
          ),
          const _MarkDuplicateReadSection(),

          // ── Display (Mohyeong-specific) ─────────────────────────────
          const PrefSectionHeader('Display'),
          PrefSwitchRaw(
            title: 'Show continue reading button',
            subtitle: 'Overlay a play button on cards to resume the next '
              'unread chapter.',
            value: showContinueReading,
            onChanged: ref
                .read(showContinueReadingButtonProvider.notifier)
                .setEnabled,
          ),

          // ── Badges ──────────────────────────────────────────────────
          const PrefSectionHeader('Badges'),
          PrefSwitchRaw(
            title: 'Unread count',
            subtitle: 'Show the number of unread chapters on each card',
            value: showUnreadBadge,
            onChanged: ref.read(displayUnreadBadgeProvider.notifier).setEnabled,
          ),
          PrefSwitchRaw(
            title: 'Downloaded count',
            subtitle: 'Show the number of downloaded chapters on each card',
            value: showDownloadBadge,
            onChanged: ref.read(displayDownloadBadgeProvider.notifier).setEnabled,
          ),
          PrefSwitchRaw(
            title: 'Local source chip',
            subtitle: 'Mark cards backed by the built-in Local source',
            value: showLocalBadge,
            onChanged: ref.read(displayLocalBadgeProvider.notifier).setEnabled,
          ),
          PrefSwitchRaw(
            title: 'Language code chip',
            subtitle: "Show the source's language code on each card.",
            value: showLanguageBadge,
            onChanged:
                ref.read(displayLanguageBadgeProvider.notifier).setEnabled,
          ),
        ],
    );
  }
}

/// "Automatic updates device restrictions" — the Wi-Fi / unmetered / charging
/// constraints applied to the background sweep. Toggling a row updates
/// [libraryUpdateDeviceRestrictionProvider]; a `main.dart` listener
/// re-registers the workmanager task so the new `Constraints` take effect.
/// Disabled (greyed) when the interval is "Off", mirroring Kotlin's
/// `enabled = autoUpdateInterval > 0`.
class _DeviceRestrictionSection extends ConsumerWidget {
  const _DeviceRestrictionSection({required this.enabled});

  final bool enabled;

  static const _entries = <(String, String)>[
    (DeviceRestriction.onlyOnWifi, 'Only on Wi-Fi'),
    (DeviceRestriction.networkNotMetered, 'Only on unmetered network'),
    (DeviceRestriction.charging, 'When charging'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryUpdateDeviceRestrictionProvider);
    final notifier =
        ref.read(libraryUpdateDeviceRestrictionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PrefSectionHeader('Automatic updates device restrictions'),
        for (final (token, label) in _entries)
          PrefCheckRaw(
            label: label,
            value: selected.contains(token),
            onChanged: enabled
                ? (checked) {
                    final next = {...selected};
                    if (checked ?? false) {
                      next.add(token);
                    } else {
                      next.remove(token);
                    }
                    notifier.set(next);
                  }
                : null,
          ),
      ],
    );
  }
}

/// The "Smart update" restriction checkboxes. Toggling a row adds/removes
/// its token from the [libraryUpdateMangaRestrictionProvider] set. Labels +
/// token order mirror Mihon's `SettingsLibraryScreen` multi-select.
class _SmartUpdateSection extends ConsumerWidget {
  const _SmartUpdateSection();

  static const _entries = <(String, String)>[
    (MangaUpdateRestriction.hasUnread, 'Skip entries with unread chapter(s)'),
    (MangaUpdateRestriction.nonRead, 'Skip unstarted entries'),
    (MangaUpdateRestriction.nonCompleted, 'Skip entries with "Completed" '
        'status'),
    (MangaUpdateRestriction.outsideReleasePeriod, 'Predict next release time'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(libraryUpdateMangaRestrictionProvider);
    final notifier =
        ref.read(libraryUpdateMangaRestrictionProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PrefSectionHeader('Smart update'),
        for (final (token, label) in _entries)
          PrefCheckRaw(
            label: label,
            value: selected.contains(token),
            onChanged: (checked) {
              final next = {...selected};
              if (checked ?? false) {
                next.add(token);
              } else {
                next.remove(token);
              }
              notifier.set(next);
            },
          ),
      ],
    );
  }
}

/// Kotlin's "Mark duplicate read chapter as read" MultiSelectListPreference
/// (Behavior group): two independent checkboxes for the `existing` / `new`
/// tokens. Verbatim Mihon strings.
class _MarkDuplicateReadSection extends ConsumerWidget {
  const _MarkDuplicateReadSection();

  static const _entries = <(String, String)>[
    (MarkDuplicateRead.readExisting, 'After reading a chapter'),
    (MarkDuplicateRead.readNew, 'After fetching new chapter'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(markDuplicateReadChapterAsReadProvider);
    final notifier =
        ref.read(markDuplicateReadChapterAsReadProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PrefSectionHeader('Mark duplicate read chapter as read'),
        for (final (token, label) in _entries)
          PrefCheckRaw(
            label: label,
            value: selected.contains(token),
            onChanged: (checked) {
              final next = {...selected};
              if (checked ?? false) {
                next.add(token);
              } else {
                next.remove(token);
              }
              notifier.set(next);
            },
          ),
      ],
    );
  }
}

/// "Default category" picker (Kotlin SettingsLibraryScreen's ListPreference
/// over `defaultCategory`): "Always ask" (-1), "Default" (0 — the implicit
/// uncategorized bucket), or any user category by id.
class _DefaultCategoryTile extends ConsumerWidget {
  const _DefaultCategoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(userCategoriesProvider).valueOrNull ?? const <Category>[];
    final current = ref.watch(defaultCategoryProvider);
    String label;
    if (current == -1) {
      label = 'Always ask';
    } else if (current == 0) {
      label = 'Default';
    } else {
      label = 'Always ask';
      for (final c in categories) {
        if (c.id == current) {
          label = c.name;
          break;
        }
      }
    }
    return PrefRow(
      title: 'Default category',
      subtitle: label,
      onTap: () async {
        final picked = await pickPref<int>(
          context,
          title: 'Default category',
          selected: current,
          options: [
            (-1, 'Always ask'),
            (0, 'Default'),
            for (final c in categories) (c.id, c.name),
          ],
        );
        if (picked != null) {
          await ref.read(defaultCategoryProvider.notifier).set(picked);
        }
      },
    );
  }
}

/// Picker for one chapter-swipe direction (Kotlin SettingsLibraryScreen's
/// swipe ListPreferences): Disabled / Bookmark / Mark as read / Download.
class _SwipeActionTile extends ConsumerWidget {
  const _SwipeActionTile({required this.title, required this.provider});

  final String title;
  final NotifierProvider<StringPrefNotifier, String> provider;

  // Kotlin entry order.
  static const _order = [
    ChapterSwipeAction.disabled,
    ChapterSwipeAction.toggleBookmark,
    ChapterSwipeAction.toggleRead,
    ChapterSwipeAction.download,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ChapterSwipeAction.fromName(ref.watch(provider));
    return PrefRow(
      title: title,
      subtitle: current.label,
      onTap: () async {
        final picked = await pickPref<ChapterSwipeAction>(
          context,
          title: title,
          selected: current,
          options: [
            for (final a in _order) (a, a.label),
          ],
        );
        if (picked != null) {
          await ref.read(provider.notifier).set(picked.storageName);
        }
      },
    );
  }
}
