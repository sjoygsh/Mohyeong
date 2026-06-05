import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';
import '../../data/reader/reader_behavior_preferences.dart';
import '../../data/reader/reader_preferences.dart';
import '../../domain/reader/model/reading_mode.dart';

/// Reader sub-screen: global default reading mode + visual prefs
/// (background colour, colour filter). Per-manga overrides live in
/// the reader's tune menu — these are the fallbacks.
class ReaderSettingsScreen extends ConsumerWidget {
  const ReaderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerMode = ref.watch(readerPreferencesProvider);
    final readerNotifier = ref.read(readerPreferencesProvider.notifier);
    final orientation = ref.watch(readerOrientationProvider);
    final background = ref.watch(readerBackgroundProvider);
    final colorFilterEnabled = ref.watch(readerColorFilterEnabledProvider);
    final colorFilterMode = ref.watch(readerColorFilterModeProvider);
    final autoHideSeconds = ref.watch(readerAutoHideChromeSecondsProvider);
    final doubleTapSpeed = ref.watch(readerDoubleTapAnimSpeedProvider);
    final scaleType = ref.watch(readerImageScaleTypeProvider);
    final zoomStart = ref.watch(readerZoomStartProvider);
    final navModePager = ref.watch(readerNavModePagerProvider);
    final navModeWebtoon = ref.watch(readerNavModeWebtoonProvider);
    final flashEnabled = ref.watch(readerFlashOnPageChangeProvider);
    final flashColor = ref.watch(readerFlashColorProvider);
    final flashInterval = ref.watch(readerFlashIntervalProvider);
    final flashDuration = ref.watch(readerFlashDurationProvider);
    final sidePadding = ref.watch(readerWebtoonSidePaddingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reader')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'General',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
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
                await readerNotifier.setMode(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Rotation'),
            subtitle: Text(orientation.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderOrientation>(
                context: context,
                builder: (_) => _OrientationPickerDialog(current: orientation),
              );
              if (picked != null) {
                await ref
                    .read(readerOrientationProvider.notifier)
                    .set(picked);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            title: const Text('Background colour'),
            subtitle: Text(background.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderBackground>(
                context: context,
                builder: (_) =>
                    _ReaderBackgroundPickerDialog(current: background),
              );
              if (picked != null) {
                await ref
                    .read(readerBackgroundProvider.notifier)
                    .set(picked);
              }
            },
          ),
          SwitchListTile(
            title: const Text('Colour filter'),
            subtitle: const Text('Tint pages with a custom ARGB colour.'),
            value: colorFilterEnabled,
            onChanged: (v) =>
                ref.read(readerColorFilterEnabledProvider.notifier).set(v),
          ),
          if (colorFilterEnabled) ...[
            const _ColorFilterChannelSliders(),
            ListTile(
              title: const Text('Colour filter blend mode'),
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
          _PrefSwitch(
            title: 'Greyscale',
            subtitle: 'Desaturate page art.',
            provider: readerGrayscaleProvider,
          ),
          _PrefSwitch(
            title: 'Invert colours',
            subtitle: 'Render pages as a colour negative.',
            provider: readerInvertedColorsProvider,
          ),
          _PrefSwitch(
            title: 'Custom brightness',
            subtitle: 'Set a fixed screen brightness while reading.',
            provider: readerCustomBrightnessProvider,
          ),
          if (ref.watch(readerCustomBrightnessProvider))
            const _BrightnessSlider(),
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
          ListTile(
            title: const Text('Zoom start position'),
            subtitle: Text(zoomStart.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderZoomStart>(
                context: context,
                builder: (_) => _ZoomStartPickerDialog(current: zoomStart),
              );
              if (picked != null) {
                await ref
                    .read(readerZoomStartProvider.notifier)
                    .set(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Webtoon side padding'),
            subtitle: Text(_sidePaddingLabel(sidePadding)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) =>
                    _SidePaddingPickerDialog(current: sidePadding),
              );
              if (picked != null) {
                await ref
                    .read(readerWebtoonSidePaddingProvider.notifier)
                    .set(picked);
              }
            },
          ),
          _PrefSwitch(
            title: 'Crop borders',
            subtitle: 'Trim solid page margins off each page.',
            provider: readerCropBordersProvider,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Behaviour',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _PrefSwitch(
            title: 'Fullscreen',
            subtitle: 'Hide the system bars while reading.',
            provider: readerFullscreenProvider,
          ),
          _PrefSwitch(
            title: 'Keep screen on',
            subtitle: 'Prevent the screen from dimming while reading.',
            provider: readerKeepScreenOnProvider,
          ),
          _PrefSwitch(
            title: 'Show page number',
            subtitle: 'Display the current / total page indicator.',
            provider: readerShowPageNumberProvider,
          ),
          _PrefSwitch(
            title: 'Show reading-mode label',
            subtitle: 'Flash the active reading mode when a chapter opens.',
            provider: readerShowReadingModeProvider,
          ),
          _PrefSwitch(
            title: 'Animate page transitions',
            subtitle: 'Slide between pages in the paged readers.',
            provider: readerPageTransitionsProvider,
          ),
          _PrefSwitch(
            title: 'Tap to navigate',
            subtitle: 'Tap the screen edges to turn pages (paged modes).',
            provider: readerTapToNavigateProvider,
          ),
          _PrefSwitch(
            title: 'Invert tap zones',
            subtitle: 'Swap the left/right page-turn zones.',
            provider: readerTapNavigateInvertProvider,
          ),
          _PrefSwitch(
            title: 'Volume key navigation',
            subtitle: 'Turn pages (or scroll) with the volume keys.',
            provider: readerVolumeKeysProvider,
          ),
          _PrefSwitch(
            title: 'Invert volume keys',
            subtitle: 'Volume up advances, volume down goes back.',
            provider: readerVolumeKeysInvertedProvider,
          ),
          ListTile(
            title: const Text('Double-tap zoom speed'),
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
          ListTile(
            title: const Text('Tap zones (paged)'),
            subtitle: Text(navModePager.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderNavMode>(
                context: context,
                builder: (_) => _NavModePickerDialog(
                  title: 'Tap zones (paged)',
                  current: navModePager,
                ),
              );
              if (picked != null) {
                await ref
                    .read(readerNavModePagerProvider.notifier)
                    .set(picked);
              }
            },
          ),
          ListTile(
            title: const Text('Tap zones (webtoon)'),
            subtitle: Text(navModeWebtoon.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDialog<ReaderNavMode>(
                context: context,
                builder: (_) => _NavModePickerDialog(
                  title: 'Tap zones (webtoon)',
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
          _PrefSwitch(
            title: 'Long-tap actions',
            subtitle: 'Long-press a page for the page actions menu.',
            provider: readerLongTapProvider,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'E-Ink',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _PrefSwitch(
            title: 'Flash on page change',
            subtitle: 'Briefly flash the screen to clear e-paper ghosting.',
            provider: readerFlashOnPageChangeProvider,
          ),
          if (flashEnabled) ...[
            ListTile(
              title: const Text('Flash colour'),
              subtitle: Text(flashColor.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDialog<ReaderFlashColor>(
                  context: context,
                  builder: (_) => _FlashColorPickerDialog(current: flashColor),
                );
                if (picked != null) {
                  await ref
                      .read(readerFlashColorProvider.notifier)
                      .set(picked);
                }
              },
            ),
            _FlashIntervalSlider(value: flashInterval),
            _FlashDurationSlider(value: flashDuration),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Chapter navigation',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _PrefSwitch(
            title: 'Skip read chapters',
            subtitle: 'Jump past chapters already marked read.',
            provider: readerSkipReadProvider,
          ),
          _PrefSwitch(
            title: 'Skip filtered chapters',
            subtitle: "Skip chapters hidden by the manga's chapter filters.",
            provider: readerSkipFilteredProvider,
          ),
          _PrefSwitch(
            title: 'Skip duplicate chapters',
            subtitle: 'Skip chapters that repeat an adjacent chapter number.',
            provider: readerSkipDupeProvider,
          ),
          _PrefSwitch(
            title: 'Always show chapter transition',
            subtitle: 'Show the transition screen between chapters.',
            provider: readerAlwaysShowTransitionProvider,
          ),
        ],
      ),
    );
  }
}

/// Thin `SwitchListTile` wired to a bool [BoolPrefNotifier] provider.
/// Keeps the long settings list declarative.
class _PrefSwitch extends ConsumerWidget {
  const _PrefSwitch({
    required this.title,
    required this.subtitle,
    required this.provider,
  });

  final String title;
  final String subtitle;
  final NotifierProvider<BoolPrefNotifier, bool> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => ref.read(provider.notifier).set(v),
    );
  }
}

/// Slider for [readerBrightnessValueProvider] (1..100 percent), shown only
/// while custom brightness is enabled.
class _BrightnessSlider extends ConsumerWidget {
  const _BrightnessSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(readerBrightnessValueProvider).clamp(1, 100);
    return ListTile(
      title: const Text('Brightness level'),
      subtitle: Slider(
        min: 1,
        max: 100,
        divisions: 99,
        value: value.toDouble(),
        label: '$value%',
        onChanged: (v) => ref
            .read(readerBrightnessValueProvider.notifier)
            .set(v.round()),
      ),
      trailing: Text('$value%'),
    );
  }
}

String _animSpeedLabel(int ms) {
  if (ms <= 0) return 'No animation';
  return '$ms ms';
}

class _DoubleTapSpeedPickerDialog extends StatelessWidget {
  const _DoubleTapSpeedPickerDialog({required this.current});

  final int current;

  static const _options = <int>[0, 250, 500];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Double-tap zoom speed'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 500,
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

String _sidePaddingLabel(int pct) => pct <= 0 ? 'None' : '$pct%';

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

class _ZoomStartPickerDialog extends StatelessWidget {
  const _ZoomStartPickerDialog({required this.current});

  final ReaderZoomStart current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Zoom start position'),
      children: [
        RadioGroup<ReaderZoomStart>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final z in ReaderZoomStart.values)
                RadioListTile<ReaderZoomStart>(
                  value: z,
                  title: Text(z.label),
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

class _FlashColorPickerDialog extends StatelessWidget {
  const _FlashColorPickerDialog({required this.current});

  final ReaderFlashColor current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Flash colour'),
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

class _ColorFilterModePickerDialog extends StatelessWidget {
  const _ColorFilterModePickerDialog({required this.current});

  final ReaderColorFilterMode current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Blend mode'),
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
        _channel(context, 'Alpha', a, (v) => setChannel(24, v)),
        _channel(context, 'Red', r, (v) => setChannel(16, v)),
        _channel(context, 'Green', g, (v) => setChannel(8, v)),
        _channel(context, 'Blue', b, (v) => setChannel(0, v)),
      ],
    );
  }

  Widget _channel(
    BuildContext context,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return ListTile(
      title: Text(label),
      subtitle: Slider(
        min: 0,
        max: 255,
        divisions: 255,
        value: value.toDouble(),
        label: '$value',
        onChanged: (v) => onChanged(v.round()),
      ),
      trailing: Text('$value'),
    );
  }
}

/// Flash interval slider (1..10 pages). Mihon `pref_reader_flash_interval`.
class _FlashIntervalSlider extends ConsumerWidget {
  const _FlashIntervalSlider({required this.value});

  final int value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = value.clamp(1, 10);
    return ListTile(
      title: const Text('Flash interval'),
      subtitle: Slider(
        min: 1,
        max: 10,
        divisions: 9,
        value: v.toDouble(),
        label: '$v page${v == 1 ? '' : 's'}',
        onChanged: (n) =>
            ref.read(readerFlashIntervalProvider.notifier).set(n.round()),
      ),
      trailing: Text('$v'),
    );
  }
}

/// Flash duration slider. Mihon stores raw ms with MILLI_CONVERSION=100
/// (slider 1..15 → 100..1500ms). `pref_reader_flash_duration`.
class _FlashDurationSlider extends ConsumerWidget {
  const _FlashDurationSlider({required this.value});

  final int value;

  static const _milliConversion = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = (value / _milliConversion).round().clamp(1, 15);
    return ListTile(
      title: const Text('Flash duration'),
      subtitle: Slider(
        min: 1,
        max: 15,
        divisions: 14,
        value: steps.toDouble(),
        label: '${steps * _milliConversion} ms',
        onChanged: (n) => ref
            .read(readerFlashDurationProvider.notifier)
            .set(n.round() * _milliConversion),
      ),
      trailing: Text('${steps * _milliConversion} ms'),
    );
  }
}

class _SidePaddingPickerDialog extends StatelessWidget {
  const _SidePaddingPickerDialog({required this.current});

  final int current;

  static const _options = <int>[0, 5, 10, 15, 20, 25];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Webtoon side padding'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 0,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_sidePaddingLabel(v)),
                ),
            ],
          ),
        ),
      ],
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
      title: const Text('Rotation'),
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
      title: const Text('Background colour'),
      children: [
        RadioGroup<ReaderBackground>(
          groupValue: current,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in ReaderBackground.values)
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

