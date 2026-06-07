import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/preferences/typed_preferences.dart';

/// A `SwitchListTile` bound to a bool [BoolPrefNotifier] provider. Shared
/// across the settings sub-screens so the long preference lists stay
/// declarative.
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
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged:
          enabled ? (v) => ref.read(provider.notifier).set(v) : null,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: clamped.toDouble(),
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: max - min,
                  label: '$clamped',
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text('$clamped', textAlign: TextAlign.end),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A section header row matching the bold labels Mihon uses to group
/// related preferences.
class PrefSectionHeader extends StatelessWidget {
  const PrefSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
