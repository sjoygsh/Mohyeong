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
/// exposed. Remaining deliberate omissions vs Kotlin: the webtoon-specific
/// dual-page split/invert + rotate variants (paged-only here), and Kotlin's
/// 4-way tap-invert modes, which are a single horizontal-invert bool here
/// (what `navRegionAt` consumes), so it renders as a checkbox.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';
// The reader's sliders are the same control as the ones in Settings →
// Reader, so they are literally the same widget.
import '../settings/pref_tiles.dart';
import '../tide/tide.dart';

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
    return TideSheetPanel(
      // Scrollable so landscape (short viewport) doesn't overflow — Kotlin's
      // AdaptiveSheet scrolls its content the same way.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: TideText.display(21)),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
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
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.onUseDefault != null) ...[
                  Expanded(
                    child: TideButton(
                      label: 'Use default',
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onUseDefault!();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TideButton(
                    label: 'Apply',
                    primary: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onApply(_selected);
                    },
                  ),
                ),
              ],
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
    return TideGlass(
      radius: 16,
      tintTop: selected ? 0.13 : 0.06,
      tintBottom: selected ? 0.05 : 0.02,
      highlight: selected ? 0.20 : 0.12,
      border: selected ? 0.22 : 0.08,
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 21,
            color: selected ? TideColors.accent : TideColors.textAt(0.62),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TideText.caption(
              size: 11,
              opacity: selected ? 0.9 : 0.5,
            ),
          ),
        ],
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            TideSegmented(
              labels: const ['Mode', 'General', 'Filter'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 14),
            // Only the visible tab is built. A TabBarView would build all
            // three, and two of them watch a dozen pref providers each.
            Expanded(
              child: switch (_tab) {
                0 => _buildReadingModeTab(),
                1 => _buildGeneralTab(),
                _ => _buildColorFilterTab(),
              },
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
              TideChip(
  label: m.label,
  selected: m == _mode,
  onTap: () {
                  setState(() => _mode = m);
                  widget.onChangeMode(m);
                },
),
          ],
        ),
        _ChipRow(
          title: 'Rotation',
          children: [
            TideChip(
  label: 'Default',
  selected: _orientation == null,
  onTap: () {
                setState(() => _orientation = null);
                widget.onChangeOrientation(null);
              },
),
            for (final o in ReaderOrientation.values)
              TideChip(
  label: o.label,
  selected: o == _orientation,
  onTap: () {
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
            TideChip(
  label: m.label,
  selected: m == navMode,
  onTap: () => ref.read(readerNavModePagerProvider.notifier).set(m),
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
            TideChip(
  label: t.label,
  selected: t == ref.watch(readerImageScaleTypeProvider),
  onTap: () => ref.read(readerImageScaleTypeProvider.notifier).set(t),
),
        ],
      ),
      _ChipRow(
        title: 'Zoom start position',
        children: [
          for (final z in ReaderZoomStart.values)
            TideChip(
  label: z.label,
  selected: z == ref.watch(readerZoomStartProvider),
  onTap: () => ref.read(readerZoomStartProvider.notifier).set(z),
),
        ],
      ),
      _PrefCheckbox(
        label: 'Automatically zoom into wide images',
        provider: readerLandscapeZoomProvider,
      ),
      _PrefCheckbox(
        label: 'Pan wide images',
        provider: readerNavigateToPanProvider,
      ),
      _PrefCheckbox(
        label: 'Split wide pages',
        provider: readerDualPageSplitProvider,
      ),
      if (ref.watch(readerDualPageSplitProvider))
        _PrefCheckbox(
          label: 'Invert split page placement',
          provider: readerDualPageInvertProvider,
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
            TideChip(
  label: m.label,
  selected: m == navMode,
  onTap: () => ref.read(readerNavModeWebtoonProvider.notifier).set(m),
),
        ],
      ),
      if (navMode != ReaderNavMode.disabled)
        _PrefCheckbox(
          label: 'Invert tap zones',
          provider: readerTapNavigateInvertProvider,
        ),
      _PrefCheckbox(
        label: 'Crop borders',
        provider: readerCropBordersWebtoonProvider,
      ),
      _PrefCheckbox(
        label: 'Double tap to zoom',
        provider: readerWebtoonDoubleTapZoomProvider,
      ),
      _PrefCheckbox(
        label: 'Disable zoom out',
        provider: readerWebtoonDisableZoomOutProvider,
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
              TideChip(
  label: b.label,
  selected: b == background,
  onTap: () => ref.read(readerBackgroundProvider.notifier).set(b),
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
        // Kotlin pref_cutout_short — applied while fullscreen.
        _PrefCheckbox(
          label: 'Show content in cutout area',
          provider: readerCutoutShortProvider,
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
          label: 'Always show chapter transition',
          provider: readerAlwaysShowTransitionProvider,
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
                TideChip(
  label: c.label,
  selected: c == flashColor,
  onTap: () => ref.read(readerFlashColorProvider.notifier).set(c),
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
        // Not a _PrefCheckbox: this one's notifier isn't a plain bool pref.
        _CheckRow(
          label: 'Custom color filter',
          value: filterOn,
          onChanged: (v) =>
              ref.read(readerColorFilterEnabledProvider.notifier).set(v),
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
                TideChip(
  label: m.label,
  selected: m == filterMode,
  onTap: () => ref.read(readerColorFilterModeProvider.notifier).set(m),
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
  Widget build(BuildContext context) => TideSectionHeader(
        label: label,
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      );
}

/// Kotlin `SettingsChipRow`: a labelled, horizontally scrolling row of chips.
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
          // The row bleeds to the panel's edge so a long set of chips reads
          // as continuing off-screen rather than stopping short.
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (i, chip) in children.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                chip,
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
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
  Widget build(BuildContext context, WidgetRef ref) => _CheckRow(
        label: label,
        value: ref.watch(provider),
        onChanged: (v) => ref.read(provider.notifier).set(v),
      );
}

/// One checkbox on its own pane of glass. Set rows carry a little more tint
/// and a brighter edge, so a screen of them shows its state at a glance.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: TideGlass(
        radius: 14,
        tintTop: value ? 0.115 : 0.06,
        tintBottom: value ? 0.042 : 0.02,
        highlight: value ? 0.18 : 0.12,
        border: value ? 0.17 : 0.08,
        padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
        child: TideCheck(label: label, value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Kotlin `SliderItem`. The same control as Settings → Reader, so the two
/// surfaces don't disagree about what a slider looks like.
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
    return PrefSlider(
      title: label,
      subtitle: valueLabel,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }
}
