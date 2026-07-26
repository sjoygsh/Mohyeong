import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/track/track_preferences.dart';
import '../../data/track/tracker.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/track/model/tracker.dart';
import '../settings/pref_tiles.dart';

/// Trackers settings page — lists every registered tracker and lets the
/// user log in / out. Split into "Online" and "Advanced" sections matching
/// Mihon's layout.
class TrackersSettingsScreen extends ConsumerWidget {
  const TrackersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(trackerRegistryProvider);
    final online = registry.all
        .where((t) => t.category == TrackerCategory.online)
        .toList(growable: false);
    final advanced = registry.all
        .where((t) => t.category == TrackerCategory.advanced)
        .toList(growable: false);
    return PrefScaffold(
      title: 'Tracking',
      actions: [
        TideIconButton(
          icon: Icons.help_outline,
          onTap: () => launchUrl(
            Uri.parse('https://sjoygsh.github.io/Mohyeong/help.html#tracking'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ],
      children: [
          // Top-level tracking behaviour (Mihon SettingsTrackingScreen: three
          // ungrouped items above the "Trackers" service group).
          PrefSwitch(
            title: 'Update progress after reading',
            provider: autoUpdateTrackProvider,
          ),
          PrefSwitch(
            title: 'Track by volume',
            subtitle: 'Report volume number to trackers instead of chapter '
                'number, when known',
            provider: trackByVolumeProvider,
          ),
          Consumer(
            builder: (context, ref, _) {
              final state = AutoTrackState.fromKey(
                ref.watch(autoUpdateTrackOnMarkReadProvider),
              );
              return PrefRow(
                icon: Icons.done_all,
                title: 'Update progress when marked as read',
                subtitle: state.label,
                onTap: () => _pickAutoTrackState(context, ref, state),
              );
            },
          ),
          const _SectionHeader('Trackers'),
          for (final t in online) _TrackerTile(tracker: t),
          const _InfoText(
            'One-way sync to update the chapter progress in external tracker '
            'services. Set up tracking for individual entries from their '
            'tracking button.',
          ),
          if (advanced.isNotEmpty) ...[
            const _SectionHeader('Enhanced trackers'),
            for (final t in advanced) _TrackerTile(tracker: t),
            const _InfoText(
              'Some source extensions include built-in tracking. Install one '
              'of the matching extensions below to enable — entries are then '
              'tracked automatically when added to your library.',
            ),
          ],
      ],
    );
  }

  /// Single-choice radio dialog for the "Update progress when marked as read"
  /// preference (Mihon `autoUpdateTrackOnMarkRead` ListPreference:
  /// Always / Always ask / Never).
  Future<void> _pickAutoTrackState(
    BuildContext context,
    WidgetRef ref,
    AutoTrackState current,
  ) async {
    final picked = await showDialog<AutoTrackState>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Update progress when marked as read'),
        children: [
          RadioGroup<AutoTrackState>(
            groupValue: current,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final state in AutoTrackState.values)
                  RadioListTile<AutoTrackState>(
                    value: state,
                    title: Text(state.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref
          .read(autoUpdateTrackOnMarkReadProvider.notifier)
          .set(picked.key);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return PrefSectionHeader(label);
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _TrackerTile extends StatefulWidget {
  const _TrackerTile({required this.tracker});

  final Tracker tracker;

  @override
  State<_TrackerTile> createState() => _TrackerTileState();
}

class _TrackerTileState extends State<_TrackerTile> {
  bool? _loggedIn;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await widget.tracker.isLoggedIn;
    if (!mounted) return;
    setState(() => _loggedIn = value);
  }

  Future<void> _login() async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.tracker.login();
      messenger.showSnackBar(
        SnackBar(content: Text('Logged in to ${widget.tracker.name}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _working = false);
        await _refresh();
      }
    }
  }

  Future<void> _logout() async {
    await widget.tracker.logout();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _loggedIn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TideRow(
        icon: loggedIn == true ? Icons.link : Icons.link_off,
        title: widget.tracker.name,
        subtitle: loggedIn == null
            ? 'Checking…'
            : (loggedIn ? 'Logged in' : 'Not logged in'),
        lit: loggedIn == true,
        onTap: _working ? null : (loggedIn == true ? _logout : _login),
        trailing: _working
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: TideColors.accent,
                ),
              )
            : Text(
                loggedIn == true ? 'Log out' : 'Log in',
                style: TideText.title(size: 13)
                    .copyWith(color: TideColors.accent),
              ),
      ),
    );
  }
}
