import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';
import 'pref_tiles.dart';

/// Settings → Reader. Mirrors Mihon's `SettingsReaderScreen` structure:
/// five ungrouped items up top, then the Display / E-Ink / Reading /
/// Paged / Long strip / Navigation / Actions groups, with verbatim labels.
///
/// Intentional divergences from Mihon:
/// - "Show content in cutout area" omitted (cutout drawing not wired).
/// - "Always show chapter transition" omitted — the Flutter reader has no
///   chapter-transition page (it auto-advances), so the pref would be a
///   dead switch.
/// - "Zoom start position" and "Automatically zoom into wide images"
///   omitted — the paged viewer doesn't consume them yet (deferred viewer
///   work); exposing them would be dishonest.
/// - "Navigate to pan", "Split tall images", dual-page split/invert, and
///   "Hide menu on scroll" threshold omitted — features absent.
/// - "Invert tap zones" is a single shared on/off (Mihon has a per-viewer
///   4-way list); it appears in both Paged and Long strip bound to the
///   same pref because it genuinely affects both viewers.
/// - "Crop borders" is shared across viewers (Mihon has per-viewer prefs).
/// - "Create folder per manga" omitted (download layout is fixed).
/// - Mohyeong extras: "Auto-hide chrome" (Display) and "Tap to navigate"
///   (Navigation), plus the colour-filter/brightness block Mihon keeps in
///   the in-reader sheet, surfaced here under "Color filter".
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerMode = ref.watch(readerPreferencesProvider);
    final orientation = ref.watch(readerOrientationProvider);
    final background = ref.watch(readerBackgroundProvider);
    final doubleTapSpeed = ref.watch(readerDoubleTapAnimSpeedProvider);
    final autoHideSeconds = ref.watch(readerAutoHideChromeSecondsProvider);
    final flashEnabled = ref.watch(readerFlashOnPageChangeProvider);
    final flashColor = ref.watch(readerFlashColorProvider);
    final flashInterval = ref.watch(readerFlashIntervalProvider);
    final flashDuration = ref.watch(readerFlashDurationProvider);
    final navModePager = ref.watch(readerNavModePagerProvider);
    final navModeWebtoon = ref.watch(readerNavModeWebtoonProvider);
    final scaleType = ref.watch(readerImageScaleTypeProvider);
    final rotateToFit = ref.watch(readerDualPageRotateProvider);
    final zoomStart = ref.watch(readerZoomStartProvider);
    final sidePadding = ref.watch(readerWebtoonSidePaddingProvider);
    final volumeKeys = ref.watch(readerVolumeKeysProvider);
    final colorFilterEnabled = ref.watch(readerColorFilterEnabledProvider);
    final colorFilterMode = ref.watch(readerColorFilterModeProvider);
    final customBrightness = ref.watch(readerCustomBrightnessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Default reading mode'),
            subtitle: Text(readerMode.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReadingMode>(
                context: context,
                builder: (_) => _ReadingModePickerDialog(current: readerMode),
              );
              if (picked != null) {
                await ref
                    .read(readerPreferencesProvider.notifier)
                    .setMode(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Double tap animation speed'),
            subtitle: Text(_animSpeedLabel(doubleTapSpeed)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _DoubleTapSpeedPickerDialog(current: doubleTapSpeed),
              );
              if (picked != null) {
                await ref
                    .read(readerDoubleTapAnimSpeedProvider.notifier)
                    .set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Show reading mode',
            subtitle: 'Briefly show current mode when reader is opened',
            provider: readerShowReadingModeProvider,
          ),
          PrefSwitch(
            title: 'Show tap zones overlay',
            subtitle: 'Briefly show when reader is opened',
            provider: readerShowNavOverlayProvider,
          ),
          PrefSwitch(
            title: 'Animate page transitions',
            provider: readerPageTransitionsProvider,
          ),
          const PrefSectionHeader('Display'),
          ListTile(
            title: const Text('Default rotation'),
            subtitle: Text(orientation.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderOrientation>(
                context: context,
                builder: (_) => _OrientationPickerDialog(current: orientation),
              );
              if (picked != null) {
                await ref.read(readerOrientationProvider.notifier).set(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Background color'),
            subtitle: Text(background.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderBackground>(
                context: context,
                builder: (_) =>
                    _ReaderBackgroundPickerDialog(current: background),
              );
              if (picked != null) {
                await ref.read(readerBackgroundProvider.notifier).set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Fullscreen',
            provider: readerFullscreenProvider,
          ),
          PrefSwitch(
            title: 'Keep screen on',
            provider: readerKeepScreenOnProvider,
          ),
          PrefSwitch(
            title: 'Show page number',
            provider: readerShowPageNumberProvider,
          ),
          ListTile(
            title: const Text('Auto-hide chrome'),
            subtitle: Text(_autoHideLabel(autoHideSeconds)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _ReaderAutoHideChromePickerDialog(current: autoHideSeconds),
              );
              if (picked != null) {
                await ref
                    .read(readerAutoHideChromeSecondsProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const PrefSectionHeader('E-Ink'),
          PrefSwitch(
            title: 'Flash on page change',
            subtitle: 'Reduces ghosting on e-ink displays',
            provider: readerFlashOnPageChangeProvider,
          ),
          _ValueSlider(
            title: 'Flash duration',
            value: (flashDuration / _milliConversion).round().clamp(1, 15),
            min: 1,
            max: 15,
            enabled: flashEnabled,
            valueLabel: (v) => '${v * _milliConversion} ms',
            onChanged: (v) => ref
                .read(readerFlashDurationProvider.notifier)
                .set(v * _milliConversion),
          ),
          _ValueSlider(
            title: 'Flash every',
            value: flashInterval.clamp(1, 10),
            min: 1,
            max: 10,
            enabled: flashEnabled,
            valueLabel: (v) => '$v page${v == 1 ? '' : 's'}',
            onChanged: (v) =>
                ref.read(readerFlashIntervalProvider.notifier).set(v),
          ),
          ListTile(
            title: const Text('Flash with'),
            subtitle: Text(flashColor.label),
            trailing: const Icon(Icons.chevron_right),
            enabled: flashEnabled,
            onTap: !flashEnabled
                ? null
                : () async {
                    final picked = await showDialog<ReaderFlashColor>(
                      context: context,
                      builder: (_) =>
                          _FlashColorPickerDialog(current: flashColor),
                    );
                    if (picked != null) {
                      await ref
                          .read(readerFlashColorProvider.notifier)
                          .set(picked);
                    }
                  },
          ),
          const PrefSectionHeader('Reading'),
          PrefSwitch(
            title: 'Skip chapters marked read',
            provider: readerSkipReadProvider,
          ),
          PrefSwitch(
            title: 'Skip filtered chapters',
            provider: readerSkipFilteredProvider,
          ),
          PrefSwitch(
            title: 'Skip duplicate chapters',
            provider: readerSkipDupeProvider,
          ),
          // Kotlin pref_always_show_chapter_transition — now backed by the
          // real transition page between chapters.
          PrefSwitch(
            title: 'Always show chapter transition',
            provider: readerAlwaysShowTransitionProvider,
          ),
          const PrefSectionHeader('Paged'),
          ListTile(
            title: const Text('Tap zones'),
            subtitle: Text(navModePager.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderNavMode>(
                context: context,
                builder: (_) => _NavModePickerDialog(
                  title: 'Tap zones',
                  current: navModePager,
                ),
              );
              if (picked != null) {
                await ref.read(readerNavModePagerProvider.notifier).set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Invert tap zones',
            provider: readerTapNavigateInvertProvider,
            enabled: navModePager != ReaderNavMode.disabled,
          ),
          ListTile(
            title: const Text('Scale type'),
            subtitle: Text(scaleType.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderImageScaleType>(
                context: context,
                builder: (_) => _ScaleTypePickerDialog(current: scaleType),
              );
              if (picked != null) {
                await ref
                    .read(readerImageScaleTypeProvider.notifier)
                    .set(picked);
              }
            },
          ),
          // Kotlin pref_zoom_start — now honoured by the paged viewer's
          // initial transform for wide pages.
          ListTile(
            title: const Text('Zoom start position'),
            subtitle: Text(zoomStart.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderZoomStart>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Zoom start position'),
                  children: [
                    RadioGroup<ReaderZoomStart>(
                      groupValue: zoomStart,
                      onChanged: (picked) => Navigator.of(ctx).pop(picked),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final v in ReaderZoomStart.values)
                            RadioListTile<ReaderZoomStart>(
                              title: Text(v.label),
                              value: v,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              if (picked != null) {
                await ref.read(readerZoomStartProvider.notifier).set(picked);
              }
            },
          ),
          // Kotlin pref_landscape_zoom.
          PrefSwitch(
            title: 'Automatically zoom into wide images',
            provider: readerLandscapeZoomProvider,
          ),
          PrefSwitch(
            title: 'Crop borders',
            provider: readerCropBordersProvider,
          ),
          PrefSwitch(
            title: 'Rotate wide pages to fit',
            provider: readerDualPageRotateProvider,
          ),
          PrefSwitch(
            title: 'Flip orientation of rotated wide pages',
            provider: readerDualPageRotateInvertProvider,
            enabled: rotateToFit,
          ),
          const PrefSectionHeader('Long strip'),
          ListTile(
            title: const Text('Tap zones'),
            subtitle: Text(navModeWebtoon.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderNavMode>(
                context: context,
                builder: (_) => _NavModePickerDialog(
                  title: 'Tap zones',
                  current: navModeWebtoon,
                ),
              );
              if (picked != null) {
                await ref
                    .read(readerNavModeWebtoonProvider.notifier)
                    .set(picked);
              }
            },
          ),
          PrefSwitch(
            title: 'Invert tap zones',
            provider: readerTapNavigateInvertProvider,
            enabled: navModeWebtoon != ReaderNavMode.disabled,
          ),
          // Per-viewer pref (Kotlin crop_borders_webtoon) — independent of
          // the Paged group's crop.
          PrefSwitch(
            title: 'Crop borders',
            provider: readerCropBordersWebtoonProvider,
          ),
          _ValueSlider(
            title: 'Side padding',
            value: sidePadding.clamp(0, 25),
            min: 0,
            max: 25,
            valueLabel: (v) => '$v%',
            onChanged: (v) =>
                ref.read(readerWebtoonSidePaddingProvider.notifier).set(v),
          ),
          const PrefSectionHeader('Navigation'),
          PrefSwitch(
            title: 'Tap to navigate',
            subtitle: 'Tap the screen edges to turn pages',
            provider: readerTapToNavigateProvider,
          ),
          PrefSwitch(
            title: 'Volume keys',
            provider: readerVolumeKeysProvider,
          ),
          PrefSwitch(
            title: 'Invert volume keys',
            provider: readerVolumeKeysInvertedProvider,
            enabled: volumeKeys,
          ),
          const PrefSectionHeader('Actions'),
          PrefSwitch(
            title: 'Show actions on long tap',
            provider: readerLongTapProvider,
          ),
          const PrefSectionHeader('Color filter'),
          PrefSwitch(
            title: 'Custom brightness',
            provider: readerCustomBrightnessProvider,
          ),
          if (customBrightness) const _BrightnessSlider(),
          SwitchListTile(
            title: const Text('Custom color filter'),
            value: colorFilterEnabled,
            onChanged: (v) =>
                ref.read(readerColorFilterEnabledProvider.notifier).set(v),
          ),
          if (colorFilterEnabled) ...[
            const _ColorFilterChannelSliders(),
            ListTile(
              title: const Text('Color filter blend mode'),
              subtitle: Text(colorFilterMode.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDialog<ReaderColorFilterMode>(
                  context: context,
                  builder: (_) =>
                      _ColorFilterModePickerDialog(current: colorFilterMode),
                );
                if (picked != null) {
                  await ref
                      .read(readerColorFilterModeProvider.notifier)
                      .set(picked);
                }
              },
            ),
          ],
          PrefSwitch(
            title: 'Grayscale',
            provider: readerGrayscaleProvider,
          ),
          PrefSwitch(
            title: 'Inverted',
            provider: readerInvertedColorsProvider,
          ),
        ],
      ),
    );
  }
}

/// Mihon's `ReaderPreferences.MILLI_CONVERSION` — the flash-duration
/// slider counts in steps of 100ms but the pref stores raw ms.
const _milliConversion = 100;

/// A slider row with a title and a formatted trailing value readout —
/// matches Mihon's `SliderPreference` (greyed out when [enabled] is
/// false rather than hidden).
class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final String Function(int) valueLabel;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      enabled: enabled,
      subtitle: Slider(
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        value: value.toDouble(),
        label: valueLabel(value),
        onChanged: enabled ? (v) => onChanged(v.round()) : null,
      ),
      trailing: Text(valueLabel(value)),
    );
  }
}

String _animSpeedLabel(int ms) {
  // Mihon's presets: 1 = "No animation", 500 = "Normal", 250 = "Fast".
  if (ms <= 1) return 'No animation';
  if (ms == 250) return 'Fast';
  return 'Normal';
}

class _DoubleTapSpeedPickerDialog extends StatelessWidget {
  const _DoubleTapSpeedPickerDialog({required this.current});

  final int current;

  // Kotlin entry order: No animation (1), Normal (500), Fast (250).
  static const _options = <int>[1, 500, 250];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Double tap animation speed'),
      children: [
        RadioGroup<int>(
          groupValue: current <= 1 ? 1 : (current == 250 ? 250 : 500),
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_animSpeedLabel(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _autoHideLabel(int seconds) {
  if (seconds <= 0) return 'Off';
  return 'After $seconds second${seconds == 1 ? '' : 's'}';
}

/// Slider for [readerBrightnessValueProvider] (1..100 percent), shown only
/// while custom brightness is enabled.
class _BrightnessSlider extends ConsumerWidget {
  const _BrightnessSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(readerBrightnessValueProvider).clamp(1, 100);
    return _ValueSlider(
      title: 'Brightness level',
      value: value,
      min: 1,
      max: 100,
      valueLabel: (v) => '$v%',
      onChanged: (v) =>
          ref.read(readerBrightnessValueProvider.notifier).set(v),
    );
  }
}

/// A/R/G/B sliders that pack into the single `color_filter_value` int
/// (0xAARRGGBB) Mihon stores. Each slider updates one channel of the
/// current value.
class _ColorFilterChannelSliders extends ConsumerWidget {
  const _ColorFilterChannelSliders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final argb = ref.watch(readerColorFilterValueProvider) & 0xFFFFFFFF;
    final notifier = ref.read(readerColorFilterValueProvider.notifier);
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    void setChannel(int shift, int value) {
      final mask = ~(0xFF << shift) & 0xFFFFFFFF;
      final next = (argb & mask) | ((value & 0xFF) << shift);
      // Re-sign to a Dart int the same way Mihon stores it (toSigned 32).
      notifier.set(next.toSigned(32));
    }

    return Column(
      children: [
        _channel('Alpha', a, (v) => setChannel(24, v)),
        _channel('Red', r, (v) => setChannel(16, v)),
        _channel('Green', g, (v) => setChannel(8, v)),
        _channel('Blue', b, (v) => setChannel(0, v)),
      ],
    );
  }

  Widget _channel(String label, int value, ValueChanged<int> onChanged) {
    return _ValueSlider(
      title: label,
      value: value,
      min: 0,
      max: 255,
      valueLabel: (v) => '$v',
      onChanged: onChanged,
    );
  }
}

class _ReadingModePickerDialog extends StatelessWidget {
  const _ReadingModePickerDialog({required this.current});

  final ReadingMode current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Default reading mode'),
      children: [
        RadioGroup<ReadingMode>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in ReadingMode.values)
                if (m != ReadingMode.defaultMode)
                  RadioListTile<ReadingMode>(
                    value: m,
                    title: Text(m.label),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrientationPickerDialog extends StatelessWidget {
  const _OrientationPickerDialog({required this.current});

  final ReaderOrientation current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Default rotation'),
      children: [
        RadioGroup<ReaderOrientation>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in ReaderOrientation.values)
                RadioListTile<ReaderOrientation>(
                  value: o,
                  title: Text(o.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderBackgroundPickerDialog extends StatelessWidget {
  const _ReaderBackgroundPickerDialog({required this.current});

  final ReaderBackground current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Background color'),
      children: [
        RadioGroup<ReaderBackground>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in ReaderBackground.pickerOrder)
                RadioListTile<ReaderBackground>(
                  value: b,
                  title: Text(b.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlashColorPickerDialog extends StatelessWidget {
  const _FlashColorPickerDialog({required this.current});

  final ReaderFlashColor current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Flash with'),
      children: [
        RadioGroup<ReaderFlashColor>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in ReaderFlashColor.values)
                RadioListTile<ReaderFlashColor>(
                  value: c,
                  title: Text(c.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavModePickerDialog extends StatelessWidget {
  const _NavModePickerDialog({required this.title, required this.current});

  final String title;
  final ReaderNavMode current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(title),
      children: [
        RadioGroup<ReaderNavMode>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in ReaderNavMode.values)
                RadioListTile<ReaderNavMode>(
                  value: m,
                  title: Text(m.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScaleTypePickerDialog extends StatelessWidget {
  const _ScaleTypePickerDialog({required this.current});

  final ReaderImageScaleType current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Scale type'),
      children: [
        RadioGroup<ReaderImageScaleType>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in ReaderImageScaleType.values)
                RadioListTile<ReaderImageScaleType>(
                  value: t,
                  title: Text(t.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorFilterModePickerDialog extends StatelessWidget {
  const _ColorFilterModePickerDialog({required this.current});

  final ReaderColorFilterMode current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Color filter blend mode'),
      children: [
        RadioGroup<ReaderColorFilterMode>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in ReaderColorFilterMode.values)
                RadioListTile<ReaderColorFilterMode>(
                  value: m,
                  title: Text(m.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReaderAutoHideChromePickerDialog extends StatelessWidget {
  const _ReaderAutoHideChromePickerDialog({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Auto-hide chrome'),
      children: [
        RadioGroup<int>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in ReaderAutoHideChromeNotifier.presets)
                RadioListTile<int>(
                  value: s,
                  title: Text(_autoHideLabel(s)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
