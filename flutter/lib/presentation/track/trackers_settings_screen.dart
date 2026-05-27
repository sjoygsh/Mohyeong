import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/track/tracker.dart';
import '../../data/track/tracker_registry.dart';
import '../../domain/track/model/tracker.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Trackers')),
      body: ListView(
        children: [
          const _SectionHeader('Online services'),
          for (final t in online) _TrackerTile(tracker: t),
          if (advanced.isNotEmpty) const _SectionHeader('Advanced'),
          for (final t in advanced) _TrackerTile(tracker: t),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

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
    return ListTile(
      leading: CircleAvatar(
        child: Text(widget.tracker.name.substring(0, 1)),
      ),
      title: Text(widget.tracker.name),
      subtitle: Text(loggedIn == null
          ? 'Checking…'
          : (loggedIn ? 'Logged in' : 'Not logged in')),
      trailing: _working
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: loggedIn == true ? _logout : _login,
              child: Text(loggedIn == true ? 'Log out' : 'Log in'),
            ),
    );
  }
}
