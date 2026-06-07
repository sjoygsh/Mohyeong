/// Sync configuration screen — pick a service, plug in
/// credentials, run a sync. Encrypted creds live in
/// `flutter_secure_storage` via [SyncPreferences].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_manager.dart';
import '../../data/sync/sync_preferences.dart';
import '../../data/sync/sync_scheduler.dart';
import '../../data/sync/sync_transport.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _busy = false;
  String? _lastStatus;

  // Mutable working copies, written back via [_save] when the user taps
  // Save. We avoid writing on every keystroke to keep secure-storage
  // chatter low.
  late TextEditingController _hostCtl;
  late TextEditingController _usernameCtl;
  late TextEditingController _apiKeyCtl;

  SyncPreferencesData? _data;

  @override
  void initState() {
    super.initState();
    _hostCtl = TextEditingController();
    _usernameCtl = TextEditingController();
    _apiKeyCtl = TextEditingController();
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _usernameCtl.dispose();
    _apiKeyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPrefs = ref.watch(syncPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: asyncPrefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load sync prefs: $e')),
        data: (prefs) {
          _data ??= prefs.read();
          if (_hostCtl.text.isEmpty) _hostCtl.text = _data!.host;
          if (_usernameCtl.text.isEmpty) {
            _usernameCtl.text = _data!.username;
          }
          if (_apiKeyCtl.text.isEmpty) {
            // Defer to async; runs once.
            // ignore: discarded_futures
            prefs.getApiKey().then((k) {
              if (!mounted) return;
              if (_apiKeyCtl.text.isEmpty && k.isNotEmpty) {
                setState(() => _apiKeyCtl.text = k);
              }
            });
          }
          return _buildForm(context, prefs);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, SyncPreferences prefs) {
    final data = _data!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(
          title: const Text('Sync service'),
          subtitle: Text(data.service.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy
              ? null
              : () async {
                  final picked = await showDialog<SyncService>(
                    context: context,
                    builder: (_) => _ServicePickerDialog(current: data.service),
                  );
                  if (picked == null) return;
                  setState(() => _data = data.copyWith(service: picked));
                },
        ),
        if (data.service != SyncService.none) ...[
          if (_needsHost(data.service))
            _padded(
              TextField(
                controller: _hostCtl,
                decoration: InputDecoration(
                  labelText: _hostLabel(data.service),
                  hintText: _hostHint(data.service),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          if (data.service == SyncService.webDav)
            _padded(
              TextField(
                controller: _usernameCtl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          _padded(
            TextField(
              controller: _apiKeyCtl,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _secretLabel(data.service),
                hintText: _secretHint(data.service),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(),
          // "What to sync" group (Kotlin pref_sync_data_category).
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'What to sync',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            title: const Text('Categories'),
            value: data.syncCategories,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncCategories: v)),
          ),
          SwitchListTile(
            title: const Text('Chapters'),
            value: data.syncChapters,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncChapters: v)),
          ),
          SwitchListTile(
            title: const Text('Tracking'),
            value: data.syncTracking,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncTracking: v)),
          ),
          SwitchListTile(
            title: const Text('History'),
            value: data.syncHistory,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncHistory: v)),
          ),
          const Divider(),
          // ── Automation (Kotlin pref_sync_automation) ────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Automation',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            title: const Text('Sync automatically'),
            subtitle: const Text('Run periodic syncs in the background'),
            value: data.autoSyncEnabled,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(autoSyncEnabled: v)),
          ),
          ListTile(
            title: const Text('Sync interval'),
            subtitle: Text(_intervalLabel(data.autoSyncIntervalHours)),
            trailing: const Icon(Icons.chevron_right),
            enabled: data.autoSyncEnabled && !_busy,
            onTap: () async {
              final picked = await showDialog<int>(
                context: context,
                builder: (_) => _SyncIntervalPickerDialog(
                  current: data.autoSyncIntervalHours,
                ),
              );
              if (picked != null) {
                setState(() =>
                    _data = data.copyWith(autoSyncIntervalHours: picked));
              }
            },
          ),
          SwitchListTile(
            title: const Text('Sync on app start'),
            value: data.syncOnAppStart,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncOnAppStart: v)),
          ),
          const Divider(),
          if (data.lastSyncTimestamp > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: Text(
                'Last sync: ${DateTime.fromMillisecondsSinceEpoch(data.lastSyncTimestamp)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _save(prefs),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runSync(prefs),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ),
              ],
            ),
          ),
          if (_lastStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Text(
                _lastStatus!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _save(SyncPreferences prefs) async {
    setState(() => _busy = true);
    try {
      final toSave = _data!.copyWith(
        host: _hostCtl.text.trim(),
        username: _usernameCtl.text.trim(),
      );
      await prefs.write(toSave);
      await prefs.setApiKey(_apiKeyCtl.text);
      // Apply the auto-sync schedule from the just-saved prefs (mirrors
      // Kotlin re-running SyncDataJob.setupTask when these change).
      await ref.read(syncSchedulerProvider).reschedule(
            enabled: toSave.autoSyncEnabled,
            intervalHours: toSave.autoSyncIntervalHours,
            service: toSave.service,
          );
      _setStatus('Saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync(SyncPreferences prefs) async {
    // Persist any pending edits first; running with stale values would
    // be surprising.
    await _save(prefs);

    setState(() => _busy = true);
    try {
      final manager = await ref.read(syncManagerProvider.future);
      final applied = await manager.sync();
      // Refresh local snapshot so "last sync" updates immediately.
      setState(() => _data = prefs.read());
      _setStatus('Sync complete. Applied $applied manga entries.');
    } on SyncException catch (e) {
      _setStatus(e.message);
    } catch (e) {
      _setStatus('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _lastStatus = message);
  }

  static bool _needsHost(SyncService s) =>
      s == SyncService.syncYomi || s == SyncService.webDav;

  // Kotlin uses a single "Server URL" title (pref_sync_host) for both the
  // SyncYomi and WebDAV host fields.
  static String _hostLabel(SyncService s) => 'Server URL';

  static String _hostHint(SyncService s) {
    return switch (s) {
      SyncService.syncYomi => 'https://sync.example.org',
      SyncService.webDav => 'https://dav.example.org/manga',
      _ => '',
    };
  }

  // Credential field title per service, matching Kotlin SettingsSyncScreen:
  // WebDAV → Password, Google Drive / Dropbox → Access token, else → API key.
  static String _secretLabel(SyncService s) {
    return switch (s) {
      SyncService.webDav => 'Password',
      SyncService.googleDrive => 'Access token',
      SyncService.dropbox => 'Access token',
      SyncService.syncYomi => 'API key',
      SyncService.none => 'API key',
    };
  }

  static String _secretHint(SyncService s) {
    return switch (s) {
      SyncService.googleDrive => 'OAuth token w/ drive.file scope',
      SyncService.dropbox => 'From Dropbox app console',
      _ => '',
    };
  }

  static Widget _padded(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: child,
      );
}

/// Labels for the auto-sync interval, matching Kotlin's update_*hour strings.
String _intervalLabel(int hours) {
  return switch (hours) {
    6 => 'Every 6 hours',
    12 => 'Every 12 hours',
    24 => 'Daily',
    48 => 'Every 2 days',
    _ => 'Every $hours hours',
  };
}

class _SyncIntervalPickerDialog extends StatelessWidget {
  const _SyncIntervalPickerDialog({required this.current});

  final int current;

  // Mirrors Mihon's SettingsSyncScreen entries: 6, 12, 24, 48.
  static const _options = <int>[6, 12, 24, 48];

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Sync interval'),
      children: [
        RadioGroup<int>(
          groupValue: _options.contains(current) ? current : 12,
          onChanged: (picked) => Navigator.of(context).pop(picked),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final v in _options)
                RadioListTile<int>(
                  value: v,
                  title: Text(_intervalLabel(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServicePickerDialog extends StatelessWidget {
  const _ServicePickerDialog({required this.current});
  final SyncService current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync service'),
      content: RadioGroup<SyncService>(
        groupValue: current,
        onChanged: (v) => Navigator.of(context).pop(v),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in SyncService.values)
              RadioListTile<SyncService>(value: s, title: Text(s.label)),
          ],
        ),
      ),
    );
  }
}
