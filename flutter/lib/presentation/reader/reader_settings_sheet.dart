/// In-reader quick-settings surfaces, ported from Kotlin:
///   * [ModeSelectionSheet] — the icon-grid "Reading mode" / "Rotation"
///     pickers opened from the reader's bottom action bar
///     (`ReadingModeSelectDialog.kt` / `OrientationSelectDialog.kt` +
///     `ModeSelectionDialog.kt`).
///   * [ReaderSettingsSheet] — the three-tab settings sheet opened from
///     the bottom bar's gear button (`ReaderSettingsDialog.kt` with
///     `ReadingModePage` / `GeneralSettingsPage` / `ColorFilterPage`).
///
/// Honest-wiring rule: only prefs the Flutter viewer actually consumes are
/// exposed. Deliberately omitted vs Kotlin (features not implemented yet):
/// zoom start, landscape zoom, navigate-to-pan, dual-page split/invert,
/// webtoon double-tap zoom / disable zoom-out, webtoon-specific crop &
/// rotate variants, always-show-chapter-transition, display cutout.
/// Kotlin's 4-way tap-invert modes are a single horizontal-invert bool here
/// (what `navRegionAt` consumes), so it renders as a checkbox.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';

/// Best-effort Material equivalents of Mihon's custom reading-mode
/// drawables (`ic_reader_ltr_24dp` etc. have no Material counterpart).
IconData readingModeIcon(ReadingMode mode) {
  switch (mode) {
    case ReadingMode.defaultMode:
      return Icons.menu_book_outlined;
    case ReadingMode.leftToRight:
      return Icons.east;
    case ReadingMode.rightToLeft:
      return Icons.west;
    case ReadingMode.verticalPaged:
      return Icons.south;
    case ReadingMode.webtoon:
      return Icons.view_day_outlined;
    case ReadingMode.continuousVertical:
      return Icons.view_agenda_outlined;
  }
}

/// 1:1 with Kotlin `ReaderOrientation.icon` (Material icons there too).
IconData readerOrientationIcon(ReaderOrientation orientation) {
  switch (orientation) {
    case ReaderOrientation.free:
      return Icons.screen_rotation;
    case ReaderOrientation.portrait:
      return Icons.stay_current_portrait;
    case ReaderOrientation.landscape:
      return Icons.stay_current_landscape;
    case ReaderOrientation.lockedPortrait:
      return Icons.screen_lock_portrait;
    case ReaderOrientation.lockedLandscape:
      return Icons.screen_lock_landscape;
    case ReaderOrientation.reversePortrait:
      return Icons.stay_current_portrait;
  }
}

class ModeOption<T> {
  const ModeOption(this.value, this.label, this.icon);

  final T value;
  final String label;
  final IconData icon;
}

/// Icon-grid picker with "Revert to default" / "Apply" actions — Kotlin's
/// `ModeSelectionDialog` + `SettingsIconGrid`. Selection is local until
/// Apply; Revert short-circuits straight to the per-series default.
class ModeSelectionSheet<T> extends StatefulWidget {
  const ModeSelectionSheet({
    super.key,
    required this.title,
    required this.options,
    required this.initial,
    required this.onApply,
    this.onUseDefault,
  });

  final String title;
  final List<ModeOption<T>> options;
  final T initial;
  final ValueChanged<T> onApply;

  /// Non-null when a per-series override is set — renders the
  /// "Revert to default" button (Kotlin `onUseDefault`).
  final VoidCallback? onUseDefault;

  @override
  State<ModeSelectionSheet<T>> createState() => _ModeSelectionSheetState<T>();
}

class _ModeSelectionSheetState<T> extends State<ModeSelectionSheet<T>> {
  late T _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      // Scrollable so landscape (short viewport) doesn't overflow — Kotlin's
      // AdaptiveSheet scrolls its content the same way.
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeading(widget.title),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.25,
              children: [
                for (final option in widget.options)
                  _IconToggleButton(
                    label: option.label,
                    icon: option.icon,
                    selected: option.value == _selected,
                    onTap: () => setState(() => _selected = option.value),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  if (widget.onUseDefault != null)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onUseDefault!();
                      },
                      child: const Text('Revert to default'),
                    ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onApply(_selected);
                    },
                    icon: Icon(Icons.check, color: scheme.onSecondaryContainer),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconToggleButton extends StatelessWidget {
  const _IconToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The reader's three-tab quick-settings sheet (Kotlin
/// `ReaderSettingsDialog`): Reading mode / General / Custom filter.
/// Per-series writes go through [onChangeMode] / [onChangeOrientation]
/// (persisted into `mangas.viewer` by the reader screen); everything else
/// binds straight to the global pref providers, identical to the
/// Settings → Reader screen.
class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.viewerFlags,
    required this.onChangeMode,
    required this.onChangeOrientation,
  });

  /// `mangas.viewer` at open time — seeds the per-series selections.
  final int viewerFlags;

  /// Persist a per-series reading mode ([ReadingMode.defaultMode] clears
  /// the override back to the global default).
  final ValueChanged<ReadingMode> onChangeMode;

  /// Persist a per-series orientation (`null` clears the override).
  final ValueChanged<ReaderOrientation?> onChangeOrientation;

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  // Local optimistic copies of the per-series selections — the sheet
  // outlives the reader rebuild triggered by a write, so it tracks its
  // own chips (Kotlin observes the manga flow; same net effect).
  late ReadingMode _mode = ReadingMode.fromFlag(widget.viewerFlags);
  late ReaderOrientation? _orientation =
      ReaderOrientation.fromMangaFlags(widget.viewerFlags);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Reading mode'),
                Tab(text: 'General'),
                Tab(text: 'Custom filter'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildReadingModeTab(),
                  _buildGeneralTab(),
                  _buildColorFilterTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tab 1

  Widget _buildReadingModeTab() {
    // The viewer section follows the *effective* mode, like Kotlin keys
    // off the live viewer instance (WebtoonViewer vs pager).
    final effective = _mode == ReadingMode.defaultMode
        ? ref.watch(readerPreferencesProvider)
        : _mode;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const _SheetHeading('For this series'),
        _ChipRow(
          title: 'Reading mode',
          children: [
            for (final m in ReadingMode.values)
              FilterChip(
                selected: m == _mode,
                label: Text(m.label),
                onSelected: (_) {
                  setState(() => _mode = m);
                  widget.onChangeMode(m);
                },
              ),
          ],
        ),
        _ChipRow(
          title: 'Rotation',
          children: [
            FilterChip(
              selected: _orientation == null,
              label: const Text('Default'),
              onSelected: (_) {
                setState(() => _orientation = null);
                widget.onChangeOrientation(null);
              },
            ),
            for (final o in ReaderOrientation.values)
              FilterChip(
                selected: o == _orientation,
                label: Text(o.label),
                onSelected: (_) {
                  setState(() => _orientation = o);
                  widget.onChangeOrientation(o);
                },
              ),
          ],
        ),
        if (effective.isPaged)
          ..._buildPagerSection()
        else
          ..._buildWebtoonSection(),
      ],
    );
  }

  List<Widget> _buildPagerSection() {
    final navMode = ref.watch(readerNavModePagerProvider);
    final rotateToFit = ref.watch(readerDualPageRotateProvider);
    return [
      const _SheetHeading('Paged'),
      _ChipRow(
        title: 'Tap zones',
        children: [
          for (final m in ReaderNavMode.values)
            FilterChip(
              selected: m == navMode,
              label: Text(m.label),
              onSelected: (_) =>
                  ref.read(readerNavModePagerProvider.notifier).set(m),
            ),
        ],
      ),
      if (navMode != ReaderNavMode.disabled)
        _PrefCheckbox(
          label: 'Invert tap zones',
          provider: readerTapNavigateInvertProvider,
        ),
      _ChipRow(
        title: 'Scale type',
        children: [
          for (final t in ReaderImageScaleType.values)
            FilterChip(
              selected: t == ref.watch(readerImageScaleTypeProvider),
              label: Text(t.label),
              onSelected: (_) =>
                  ref.read(readerImageScaleTypeProvider.notifier).set(t),
            ),
        ],
      ),
      _PrefCheckbox(
        label: 'Crop borders',
        provider: readerCropBordersProvider,
      ),
      _PrefCheckbox(
        label: 'Rotate wide pages to fit',
        provider: readerDualPageRotateProvider,
      ),
      if (rotateToFit)
        _PrefCheckbox(
          label: 'Flip orientation of rotated wide pages',
          provider: readerDualPageRotateInvertProvider,
        ),
    ];
  }

  List<Widget> _buildWebtoonSection() {
    final navMode = ref.watch(readerNavModeWebtoonProvider);
    final sidePadding = ref.watch(readerWebtoonSidePaddingProvider);
    return [
      const _SheetHeading('Long strip'),
      _ChipRow(
        title: 'Tap zones',
        children: [
          for (final m in ReaderNavMode.values)
            FilterChip(
              selected: m == navMode,
              label: Text(m.label),
              onSelected: (_) =>
                  ref.read(readerNavModeWebtoonProvider.notifier).set(m),
            ),
        ],
      ),
      if (navMode != ReaderNavMode.disabled)
        _PrefCheckbox(
          label: 'Invert tap zones',
          provider: readerTapNavigateInvertProvider,
        ),
      _SheetSlider(
        label: 'Side padding',
        value: sidePadding.clamp(0, 25),
        min: 0,
        max: 25,
        valueLabel: '${sidePadding.clamp(0, 25)}%',
        onChanged: (v) =>
            ref.read(readerWebtoonSidePaddingProvider.notifier).set(v),
      ),
    ];
  }

  // ---------------------------------------------------------------- tab 2

  Widget _buildGeneralTab() {
    final background = ref.watch(readerBackgroundProvider);
    final flashOn = ref.watch(readerFlashOnPageChangeProvider);
    final flashMillis = ref.watch(readerFlashDurationProvider);
    final flashInterval = ref.watch(readerFlashIntervalProvider).clamp(1, 10);
    final flashColor = ref.watch(readerFlashColorProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _ChipRow(
          title: 'Background color',
          children: [
            for (final b in ReaderBackground.pickerOrder)
              FilterChip(
                selected: b == background,
                label: Text(b.label),
                onSelected: (_) =>
                    ref.read(readerBackgroundProvider.notifier).set(b),
              ),
          ],
        ),
        _PrefCheckbox(
          label: 'Show page number',
          provider: readerShowPageNumberProvider,
        ),
        _PrefCheckbox(
          label: 'Fullscreen',
          provider: readerFullscreenProvider,
        ),
        _PrefCheckbox(
          label: 'Keep screen on',
          provider: readerKeepScreenOnProvider,
        ),
        _PrefCheckbox(
          label: 'Show actions on long tap',
          provider: readerLongTapProvider,
        ),
        _PrefCheckbox(
          label: 'Animate page transitions',
          provider: readerPageTransitionsProvider,
        ),
        _PrefCheckbox(
          label: 'Flash on page change',
          provider: readerFlashOnPageChangeProvider,
        ),
        if (flashOn) ...[
          _SheetSlider(
            label: 'Flash duration',
            value: (flashMillis ~/ 100).clamp(1, 15),
            min: 1,
            max: 15,
            valueLabel: '$flashMillis ms',
            onChanged: (v) =>
                ref.read(readerFlashDurationProvider.notifier).set(v * 100),
          ),
          _SheetSlider(
            label: 'Flash every',
            value: flashInterval,
            min: 1,
            max: 10,
            valueLabel: '$flashInterval page(s)',
            onChanged: (v) =>
                ref.read(readerFlashIntervalProvider.notifier).set(v),
          ),
          _ChipRow(
            title: 'Flash with',
            children: [
              for (final c in ReaderFlashColor.values)
                FilterChip(
                  selected: c == flashColor,
                  label: Text(c.label),
                  onSelected: (_) =>
                      ref.read(readerFlashColorProvider.notifier).set(c),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- tab 3

  Widget _buildColorFilterTab() {
    final customBrightness = ref.watch(readerCustomBrightnessProvider);
    final brightnessValue =
        ref.watch(readerBrightnessValueProvider).clamp(1, 100);
    final filterOn = ref.watch(readerColorFilterEnabledProvider);
    final filterValue = ref.watch(readerColorFilterValueProvider);
    final filterMode = ref.watch(readerColorFilterModeProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _PrefCheckbox(
          label: 'Custom brightness',
          provider: readerCustomBrightnessProvider,
        ),
        if (customBrightness)
          _SheetSlider(
            label: 'Custom brightness',
            value: brightnessValue,
            min: 1,
            max: 100,
            valueLabel: '$brightnessValue',
            onChanged: (v) =>
                ref.read(readerBrightnessValueProvider.notifier).set(v),
          ),
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Custom color filter'),
          value: filterOn,
          onChanged: (v) => ref
              .read(readerColorFilterEnabledProvider.notifier)
              .set(v ?? false),
        ),
        if (filterOn) ...[
          _channelSlider('Red', filterValue, 16),
          _channelSlider('Green', filterValue, 8),
          _channelSlider('Blue', filterValue, 0),
          _channelSlider('Alpha', filterValue, 24),
          _ChipRow(
            title: 'Color filter blend mode',
            children: [
              for (final m in ReaderColorFilterMode.values)
                FilterChip(
                  selected: m == filterMode,
                  label: Text(m.label),
                  onSelected: (_) =>
                      ref.read(readerColorFilterModeProvider.notifier).set(m),
                ),
            ],
          ),
        ],
        _PrefCheckbox(
          label: 'Grayscale',
          provider: readerGrayscaleProvider,
        ),
        _PrefCheckbox(
          label: 'Inverted',
          provider: readerInvertedColorsProvider,
        ),
      ],
    );
  }

  /// One ARGB channel slider. Packs the new channel back into the stored
  /// signed 32-bit int the same way Kotlin's `getColorValue` does.
  Widget _channelSlider(String label, int packed, int shift) {
    final channel = (packed >> shift) & 0xFF;
    return _SheetSlider(
      label: label,
      value: channel,
      min: 0,
      max: 255,
      valueLabel: '$channel',
      onChanged: (v) {
        final updated =
            ((packed & ~(0xFF << shift)) | (v << shift)).toSigned(32);
        ref.read(readerColorFilterValueProvider.notifier).set(updated);
      },
    );
  }
}

// ------------------------------------------------------------ components

class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

/// Kotlin `SettingsChipRow`: a labelled, horizontally scrolling row of
/// [FilterChip]s.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetHeading(title),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (i, chip) in children.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                chip,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Kotlin `CheckboxItem` bound to a bool pref provider.
class _PrefCheckbox extends ConsumerWidget {
  const _PrefCheckbox({required this.label, required this.provider});

  final String label;
  final NotifierProvider<BoolPrefNotifier, bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      title: Text(label),
      value: ref.watch(provider),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (v) => ref.read(provider.notifier).set(v ?? false),
    );
  }
}

/// Kotlin `SliderItem`: label + slider + value pill.
class _SheetSlider extends StatelessWidget {
  const _SheetSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String valueLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(valueLabel, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
