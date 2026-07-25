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
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: ListView(
        children: [
          // ── Categories ──────────────────────────────────────────────
          const PrefSectionHeader('Categories'),
          ListTile(
            title: const Text('Edit categories'),
            subtitle: Text(
              categoryCount == 1 ? '1 category' : '$categoryCount categories',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoriesScreen(),
              ),
            ),
          ),
          const _DefaultCategoryTile(),

          // ── Global update ───────────────────────────────────────────
          const PrefSectionHeader('Global update'),
          ListTile(
            title: const Text('Automatic updates'),
            subtitle: Text(interval.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<LibraryUpdateInterval>(
                context: context,
                builder: (_) => _IntervalPickerDialog(current: interval),
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
          // Verbatim Mihon string pref_library_update_show_tab_badge.
          PrefSwitch(
            title: 'Show unread count on Updates icon',
            provider: newShowUpdatesCountProvider,
          ),

          // ── Behavior ────────────────────────────────────────────────
          const PrefSectionHeader('Behavior'),
          // Verbatim Mihon string pref_hide_missing_chapter_indicators.
          SwitchListTile(
            title: const Text('Hide missing chapter indicators'),
            subtitle: const Text(
              'Hide the "Missing N chapters" rows between chapters with a '
              'numbering gap on the manga page',
            ),
            value: ref.watch(hideMissingChaptersProvider),
            onChanged:
                ref.read(hideMissingChaptersProvider.notifier).setEnabled,
          ),
          // Verbatim Mihon strings pref_group_chapters_by_volume / _summary.
          SwitchListTile(
            title: const Text('Group chapters by volume'),
            subtitle: const Text(
              'Show volume headers between chapter groups on the manga page',
            ),
            value: ref.watch(groupChaptersByVolumeProvider),
            onChanged:
                ref.read(groupChaptersByVolumeProvider.notifier).setEnabled,
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
          SwitchListTile(
            title: const Text('Show continue reading button'),
            subtitle: const Text(
              'Overlay a play button on cards to resume the next '
              'unread chapter.',
            ),
            value: showContinueReading,
            onChanged: ref
                .read(showContinueReadingButtonProvider.notifier)
                .setEnabled,
          ),

          // ── Badges ──────────────────────────────────────────────────
          const PrefSectionHeader('Badges'),
          SwitchListTile(
            title: const Text('Unread count'),
            subtitle: const Text(
              'Show the number of unread chapters on each card.',
            ),
            value: showUnreadBadge,
            onChanged:
                ref.read(displayUnreadBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Downloaded count'),
            subtitle: const Text(
              'Show the number of downloaded chapters on each card.',
            ),
            value: showDownloadBadge,
            onChanged:
                ref.read(displayDownloadBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Local source chip'),
            subtitle: const Text(
              'Mark cards backed by the built-in Local source.',
            ),
            value: showLocalBadge,
            onChanged:
                ref.read(displayLocalBadgeProvider.notifier).setEnabled,
          ),
          SwitchListTile(
            title: const Text('Language code chip'),
            subtitle: const Text(
              "Show the source's language code on each card.",
            ),
            value: showLanguageBadge,
            onChanged:
                ref.read(displayLanguageBadgeProvider.notifier).setEnabled,
          ),
        ],
      ),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Automatic updates device restrictions',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (token, label) in _entries)
          CheckboxListTile(
            title: Text(label),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Smart update',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (token, label) in _entries)
          CheckboxListTile(
            title: Text(label),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Mark duplicate read chapter as read',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (token, label) in _entries)
          CheckboxListTile(
            title: Text(label),
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

class _IntervalPickerDialog extends StatelessWidget {
  const _IntervalPickerDialog({required this.current});

  final LibraryUpdateInterval current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Automatic updates'),
      children: [
        RadioGroup<LibraryUpdateInterval>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in LibraryUpdateInterval.values)
                RadioListTile<LibraryUpdateInterval>(
                  value: v,
                  title: Text(v.label),
                ),
            ],
          ),
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
    return ListTile(
      title: const Text('Default category'),
      subtitle: Text(label),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Default category'),
            children: [
              RadioGroup<int>(
                groupValue: current,
                onChanged: (v) => Navigator.of(ctx).pop(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RadioListTile<int>(
                      title: Text('Always ask'),
                      value: -1,
                    ),
                    const RadioListTile<int>(
                      title: Text('Default'),
                      value: 0,
                    ),
                    for (final c in categories)
                      RadioListTile<int>(title: Text(c.name), value: c.id),
                  ],
                ),
              ),
            ],
          ),
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
    return ListTile(
      title: Text(title),
      subtitle: Text(current.label),
      onTap: () async {
        final picked = await showDialog<ChapterSwipeAction>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              RadioGroup<ChapterSwipeAction>(
                groupValue: current,
                onChanged: (v) => Navigator.of(ctx).pop(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in _order)
                      RadioListTile<ChapterSwipeAction>(
                        title: Text(a.label),
                        value: a,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (picked != null) {
          await ref.read(provider.notifier).set(picked.storageName);
        }
      },
    );
  }
}
