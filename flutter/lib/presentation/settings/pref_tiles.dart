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
    required this.subtitle,
    required this.provider,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final NotifierProvider<BoolPrefNotifier, bool> provider;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged:
          enabled ? (v) => ref.read(provider.notifier).set(v) : null,
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
