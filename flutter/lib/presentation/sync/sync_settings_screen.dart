/// Sync configuration screen — pick a service, plug in
/// credentials, run a sync. Encrypted creds live in
/// `flutter_secure_storage` via [SyncPreferences].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';

import '../settings/pref_tiles.dart';

import '../../data/sync/sync_manager.dart';
import '../../data/sync/sync_preferences.dart';
import '../../data/sync/sync_scheduler.dart';
import '../../data/sync/sync_transport.dart';
import '../util/user_message.dart';
import '../util/open_link.dart';

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

  /// Last persisted state, for the unsaved-changes check. Everything on this
  /// screen is buffered until Save, so without this, backing out threw the
  /// edits away with no indication — the one place in the app where changing
  /// a switch and leaving did not keep the change.
  SyncPreferencesData? _savedData;
  String _savedApiKey = '';
  bool _lastDirty = false;

  bool get _dirty {
    final saved = _savedData;
    final data = _data;
    if (saved == null || data == null) return false;
    return _hostCtl.text.trim() != saved.host ||
        _usernameCtl.text.trim() != saved.username ||
        _apiKeyCtl.text != _savedApiKey ||
        data.service != saved.service ||
        data.syncCategories != saved.syncCategories ||
        data.syncChapters != saved.syncChapters ||
        data.syncTracking != saved.syncTracking ||
        data.syncHistory != saved.syncHistory ||
        data.autoSyncEnabled != saved.autoSyncEnabled ||
        data.autoSyncIntervalHours != saved.autoSyncIntervalHours ||
        data.syncOnAppStart != saved.syncOnAppStart;
  }

  /// The text fields don't rebuild this screen on their own, so the back
  /// guard would never learn about a typed-but-unsaved host. Deferred a frame
  /// because the same controllers are populated during build.
  void _onFieldChanged() {
    if (_dirty == _lastDirty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dirty == _lastDirty) return;
      setState(() => _lastDirty = _dirty);
    });
  }

  @override
  void initState() {
    super.initState();
    _hostCtl = TextEditingController()..addListener(_onFieldChanged);
    _usernameCtl = TextEditingController()..addListener(_onFieldChanged);
    _apiKeyCtl = TextEditingController()..addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _usernameCtl.dispose();
    _apiKeyCtl.dispose();
    super.dispose();
  }

  /// Back with unsaved edits asks rather than silently discarding.
  Future<void> _confirmDiscard(bool didPop) async {
    if (didPop) return;
    final navigator = Navigator.of(context);
    final discard = await showTideSheet<bool>(
      context,
      (_) => const TideConfirmSheet(
        title: 'Unsaved changes',
        message: 'Leave without saving what you changed here?',
        confirmLabel: 'Discard',
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPrefs = ref.watch(syncPreferencesProvider);
    return PopScope(
      // Read live: the switches rebuild through setState, so this is always
      // current for them. _lastDirty exists only to force that rebuild when
      // a text field is what changed.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) => _confirmDiscard(didPop),
      child: Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideHeader(
              title: 'Sync',
              actions: [
                TideIconButton(
                  icon: Icons.help_outlined,
                  onTap: () => openLink(context, helpUrl('sync-overview')),
                ),
              ],
            ),
            Expanded(child: asyncPrefs.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: TideSpinner(size: 24, strokeWidth: 2),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
                userMessage(e, fallback: 'Couldn\'t load sync settings.'),
                textAlign: TextAlign.center, style: TideText.body()),
          ),
        ),
        data: (prefs) {
          _data ??= prefs.read();
          _savedData ??= _data;
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
                setState(() {
                  _apiKeyCtl.text = k;
                  _savedApiKey = k;
                });
              }
            });
          }
          return _buildForm(context, prefs);
        },
      )),
          ],
        ),
      ),
        ],
      ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, SyncPreferences prefs) {
    final data = _data!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        PrefRow(
          title: 'Sync service',
          subtitle: data.service.label,
          onTap: _busy
              ? null
              : () async {
                  final picked = await pickPref<SyncService>(
                    context,
                    title: 'Sync service',
                    options: [
                      for (final s in SyncService.values) (s, s.label),
                    ],
                    selected: data.service,
                  );
                  if (picked == null) return;
                  setState(() => _data = data.copyWith(service: picked));
                },
        ),
        if (data.service != SyncService.none) ...[
          if (_needsHost(data.service))
            _padded(
              TideField(
                controller: _hostCtl,
                label: _hostLabel(data.service),
                hintText: _hostHint(data.service),
                icon: Icons.dns_outlined,
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ),
          if (data.service == SyncService.webDav)
            _padded(
              TideField(
                controller: _usernameCtl,
                label: 'Username',
                icon: Icons.person_outlined,
                autocorrect: false,
              ),
            ),
          _padded(
            TideField(
              controller: _apiKeyCtl,
              label: _secretLabel(data.service),
              hintText: _secretHint(data.service),
              icon: Icons.key_outlined,
              obscureText: true,
              autocorrect: false,
            ),
          ),
          // "What to sync" group (Kotlin pref_sync_data_category).
          const PrefSectionHeader('What to sync'),
          PrefSwitchRaw(
            title: 'Categories',
            value: data.syncCategories,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncCategories: v)),
          ),
          PrefSwitchRaw(
            title: 'Chapters',
            value: data.syncChapters,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncChapters: v)),
          ),
          PrefSwitchRaw(
            title: 'Tracking',
            value: data.syncTracking,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncTracking: v)),
          ),
          PrefSwitchRaw(
            title: 'History',
            value: data.syncHistory,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncHistory: v)),
          ),
          // ── Automation (Kotlin pref_sync_automation) ────────────────
          const PrefSectionHeader('Automation'),
          PrefSwitchRaw(
            title: 'Sync automatically',
            subtitle: 'Run periodic syncs in the background',
            value: data.autoSyncEnabled,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(autoSyncEnabled: v)),
          ),
          PrefRow(
            title: 'Sync interval',
            subtitle: _intervalLabel(data.autoSyncIntervalHours),
            onTap: !(data.autoSyncEnabled && !_busy)
                ? null
                : () async {
                    final picked = await pickPref<int>(
                      context,
                      title: 'Sync interval',
                      options: [
                        for (final v in _intervalOptions) (v, _intervalLabel(v)),
                      ],
                      selected: _intervalOptions
                              .contains(data.autoSyncIntervalHours)
                          ? data.autoSyncIntervalHours
                          : 12,
                    );
                    if (picked != null) {
                      setState(() =>
                          _data = data.copyWith(autoSyncIntervalHours: picked));
                    }
                  },
          ),
          PrefSwitchRaw(
            title: 'Sync on app start',
            value: data.syncOnAppStart,
            onChanged: (v) =>
                setState(() => _data = data.copyWith(syncOnAppStart: v)),
          ),
          const PrefSectionHeader('Run'),
          if (data.lastSyncTimestamp > 0)
            PrefNote(
              'Last synced '
              '${tideRelative(DateTime.fromMillisecondsSinceEpoch(data.lastSyncTimestamp))}',
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Opacity(
              opacity: _busy ? 0.5 : 1,
              child: Row(
                children: [
                  Expanded(
                    child: TideButton(
                      label: 'Save',
                      onTap: _busy ? () {} : () => _save(prefs),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TideButton(
                      label: _busy ? 'Syncing…' : 'Sync now',
                      primary: true,
                      onTap: _busy ? () {} : () => _runSync(prefs),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_lastStatus != null) PrefNote(_lastStatus!),
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
      // The form is clean again — drop the back guard.
      _data = toSave;
      _savedData = toSave;
      _savedApiKey = _apiKeyCtl.text;
      _lastDirty = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync(SyncPreferences prefs) async {
    // Persist any pending edits first; running with stale values would
    // be surprising.
    await _save(prefs);

    // A sync runs for as long as the network takes and this screen can be
    // left mid-run; `setState` on an unmounted State throws. `_setStatus` and
    // the `finally` below already guarded — these two did not.
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final manager = await ref.read(syncManagerProvider.future);
      final applied = await manager.sync();
      if (!mounted) return;
      // Refresh local snapshot so "last sync" updates immediately.
      setState(() => _data = prefs.read());
      _setStatus('Sync complete. Applied $applied manga entries.');
    } on SyncException catch (e) {
      _setStatus(e.message);
    } catch (e) {
      _setStatus(userMessage(e, fallback: 'Sync failed.'));
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

/// Mirrors Mihon's SettingsSyncScreen entries.
const _intervalOptions = <int>[6, 12, 24, 48];

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

