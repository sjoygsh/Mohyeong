// ===========================================================================
// The settings vocabulary, in Tide.
//
// The settings sub-screens are built almost entirely out of these, so this
// file is where they convert. A preference row is a TideRow whose icon lights
// when the preference is on — the same "this one is active" cue the modes on
// More and the filters on the library already use — and a section is a kicker,
// not a bold word.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';
import '../tide/tide.dart';

/// A toggle bound to a bool [BoolPrefNotifier] provider. Shared across the
/// settings sub-screens so the long preference lists stay declarative.
class PrefSwitch extends ConsumerWidget {
  const PrefSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.provider,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final NotifierProvider<BoolPrefNotifier, bool> provider;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TideRow(
        icon: value ? Icons.check_circle : Icons.circle_outlined,
        title: title,
        subtitle: subtitle,
        lit: enabled && value,
        onTap: enabled ? () => ref.read(provider.notifier).set(!value) : null,
        trailing: TideSwitch(
          value: value,
          onChanged:
              enabled ? (v) => ref.read(provider.notifier).set(v) : (_) {},
        ),
      ),
    );
    // A row that cannot be changed says so by going quiet, rather than by
    // silently swallowing the tap.
    return enabled ? row : Opacity(opacity: 0.45, child: row);
  }
}

/// A row that opens something — a picker, a sub-screen, a file dialog — with
/// its CURRENT value as the subtitle, so the list answers "how is this set"
/// without opening anything.
class PrefRow extends StatelessWidget {
  const PrefRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.tune,
    this.onTap,
    this.trailing,
    this.lit = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TideRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        lit: lit,
        onTap: onTap,
        trailing: trailing ?? (onTap == null ? null : const TideChevron()),
      ),
    );
    return onTap == null ? Opacity(opacity: 0.45, child: row) : row;
  }
}

/// Explanatory copy under a preference — the small print Mihon puts beneath
/// the switches it needs to qualify.
class PrefNote extends StatelessWidget {
  const PrefNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      child: Text(
        text,
        style: TideText.caption(size: 12, opacity: 0.4).copyWith(height: 1.5),
      ),
    );
  }
}

/// An integer slider preference matching Mihon's `SliderPreference`: a
/// title (optional subtitle) above a discrete slider with a trailing value
/// readout. [value] is clamped into `[min, max]` for display so an
/// out-of-range stored value still renders.
class PrefSlider extends StatelessWidget {
  const PrefSlider({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TideGlass(
        radius: 16,
        tintTop: 0.075,
        tintBottom: 0.026,
        highlight: 0.14,
        border: 0.09,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: TideText.title())),
                Text(
                  '$clamped',
                  style: TideText.title(size: 14)
                      .copyWith(color: TideColors.accent),
                ),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: TideText.caption()),
              ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: TideColors.accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: TideColors.accentLight,
                overlayColor: TideColors.accent.withValues(alpha: 0.15),
                valueIndicatorColor: TideColors.accent,
                trackHeight: 3,
              ),
              child: Slider(
                value: clamped.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: '$clamped',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Groups related preferences. A kicker rather than a bold word — the same
/// separator every other Tide screen uses.
class PrefSectionHeader extends StatelessWidget {
  const PrefSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TideSectionHeader(
      label: label,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    );
  }
}

/// The frame every settings sub-screen sits in: Tide ground, a header with a
/// way back, and the list. Replaces `Scaffold(appBar: AppBar(...))`.
class PrefScaffold extends StatelessWidget {
  const PrefScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.floating,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  /// Anything that floats over the list — a save bar, usually.
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: TideRise(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TideHeader(title: title, actions: actions),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.only(
                        bottom: floating == null ? 28 : 108,
                      ),
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
            if (floating != null)
              Positioned(left: 16, right: 16, bottom: 24, child: floating!),
          ],
        ),
      ),
    );
  }
}
