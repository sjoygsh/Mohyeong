// ===========================================================================
// Tide browse.
//
// Three peer views — the sources you read from, the extensions that provide
// them, and migration — behind a glass segmented control rather than a
// Material TabBar. Each view is a run of glass rows.
//
// Every source is a website, so every row wears that website's own logo, read
// once off the site and cached to disk (see data/source/source_icon.dart). A
// list of thirty identical glyphs is a list you have to read every line of;
// with the real marks it becomes one you recognise. Sites that publish nothing
// usable keep the old deterministic sigil, so no row is ever blank.
// ===========================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/extension_updates.dart';
import '../../data/source/incognito_preferences.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/local_source.dart';
import '../../data/source/local_source_preferences.dart';
import '../../data/source/source_preferences.dart';
import '../home/home_screen.dart';
import '../tide/tide.dart';
import 'global_search_screen.dart';
import 'migrate_source_screen.dart';
import 'source_browse_screen.dart';
import 'source_preferences_screen.dart';
import 'sources_filter_screen.dart';
import '../util/user_message.dart';
import '../util/open_link.dart';

/// Browse hosts three views: Sources (installed sources you can browse),
/// Extensions (install / uninstall management), and Migrate (moves favourites
/// from one source to another).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  int _view = 0;

  /// Held rather than opened in build(): a stream created per rebuild
  /// re-subscribes every frame, and the header rebuilds on every view switch.
  late final Stream<List<InstalledExtension>> _installed =
      ref.read(extensionRepositoryProvider).watchInstalled();

  /// Views build on first visit and stay alive after, so switching back keeps
  /// scroll position. Lazily, though: the Extensions view probes every origin
  /// for a newer version on its first build, and the shell pre-warms this
  /// whole tab during post-launch idle — building all three up front would
  /// fire that probe on every cold start.
  final Set<int> _built = {0};

  @override
  void initState() {
    super.initState();
    // Mirrors Kotlin BrowseTab.onReselect: tapping the already-selected Browse
    // destination opens global search. The index is 2, not 3 — this went dead
    // when the Updates tab was removed and every tab after it shifted down.
    ref.listenManual<HomeReselectSignal>(homeReselectProvider, (prev, next) {
      if (next.tab != 2 || !mounted) return;
      _openGlobalSearch();
    });
  }

  void _openGlobalSearch() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GlobalSearchScreen()),
      );

  void _select(int view) {
    if (view == _view) return;
    setState(() {
      _view = view;
      _built.add(view);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(homeTabIndexProvider) == 2;
    return TickerMode(
      enabled: visible,
      child: Scaffold(
        backgroundColor: TideColors.ground,
        body: Stack(
          children: [
            const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.page)),
            Positioned.fill(
              child: TideRise(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: TideSegmented(
                        labels: const ['Sources', 'Extensions', 'Migrate'],
                        index: _view,
                        onChanged: _select,
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _view,
                        children: [
                          for (final i in const [0, 1, 2])
                            if (_built.contains(i))
                              switch (i) {
                                0 => const _SourcesView(),
                                1 => const _ExtensionsView(),
                                _ => const MigrateSourceTab(),
                              }
                            else
                              const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What the current view holds, in the design's eyebrow voice — the count is
  /// the one fact worth stating before the list itself says anything.
  Widget _kicker() {
    return StreamBuilder<List<InstalledExtension>>(
      stream: _installed,
      builder: (context, snap) {
        final count = snap.data?.length;
        final text = switch (_view) {
          2 => 'MOVE YOUR LIBRARY',
          _ when count == null => 'CATALOGUE',
          1 => '$count INSTALLED',
          _ => '$count ${count == 1 ? 'SOURCE' : 'SOURCES'}',
        };
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TideText.kicker(size: 11, color: TideColors.accent)
              .copyWith(letterSpacing: 2.0),
        );
      },
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kicker(),
                const SizedBox(height: 9),
                Text('Browse', style: TideText.display(32)),
              ],
            ),
          ),
          // Kotlin MigrateSourceTab's help action — shown only on that view,
          // the way Kotlin scopes toolbar actions per tab.
          if (_view == 2) ...[
            TideIconButton(
              icon: Icons.help_outlined,
              onTap: () => openLink(context, helpUrl('source-migration')),
            ),
            const SizedBox(width: 9),
          ],
          TideIconButton(icon: Icons.search, onTap: _openGlobalSearch),
          const SizedBox(width: 9),
          TideIconButton(
            icon: Icons.filter_list,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SourcesFilterScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

class _SourcesView extends ConsumerWidget {
  const _SourcesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(extensionRepositoryProvider);
    final prefsAsync = ref.watch(localSourcePreferencesProvider);
    final sourcePrefsAsync = ref.watch(sourcePreferencesProvider);
    return StreamBuilder<List<InstalledExtension>>(
      stream: repo.watchInstalled(),
      builder: (context, snap) {
        if (snap.hasError) return _LoadFailed(snap.error);
        if (!snap.hasData) return const _Spinner();
        final allExtensions = snap.data!;
        final sourcePrefs = sourcePrefsAsync.value;
        final localRoot = prefsAsync.value?.root;
        // Listen to the language + hidden-source sets so toggles on the
        // filter screen reflect immediately when the user pops back.
        // While prefs are still loading, fall through to "show all".
        return StreamBuilder<Set<String>>(
          stream: sourcePrefs?.watchEnabledLanguages(),
          initialData: sourcePrefs?.getEnabledLanguages(),
          builder: (context, langSnap) {
            return StreamBuilder<Set<String>>(
              stream: sourcePrefs?.watchDisabledSources(),
              initialData: sourcePrefs?.getDisabledSources(),
              builder: (context, disSnap) {
                return StreamBuilder<Set<String>>(
                  stream: sourcePrefs?.watchPinnedSources(),
                  initialData: sourcePrefs?.getPinnedSources(),
                  builder: (context, pinSnap) {
                    final enabledLangs = langSnap.data ?? const <String>{};
                    final disabledIds = disSnap.data ?? const <String>{};
                    final pinnedIds = pinSnap.data ?? const <String>{};
                    final extensions = sourcePrefs == null
                        ? allExtensions
                        : allExtensions
                            .where((e) =>
                                // Mihon treats `all`-language sources as
                                // always visible regardless of the language
                                // filter.
                                (e.lang.toLowerCase() == 'all' ||
                                        enabledLangs
                                            .contains(e.lang.toLowerCase())) &&
                                !disabledIds.contains(e.id))
                            .toList(growable: false);
                    return _list(
                      context,
                      ref,
                      extensions,
                      localRoot,
                      pinnedIds: pinnedIds,
                      sourcePrefs: sourcePrefs,
                      filtered: sourcePrefs != null &&
                          extensions.length != allExtensions.length,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<InstalledExtension> extensions,
    String? localRoot, {
    required bool filtered,
    Set<String> pinnedIds = const <String>{},
    SourcePreferences? sourcePrefs,
  }) {
    final pinned = [
      for (final e in extensions)
        if (pinnedIds.contains(e.id)) e,
    ];
    final unpinned = [
      for (final e in extensions)
        if (!pinnedIds.contains(e.id)) e,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: tideBarInset),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TideRow(
            icon: Icons.folder_outlined,
            title: 'Local source',
            subtitle:
                localRoot ?? 'Tap to choose a folder of manga on this device.',
            lit: localRoot != null,
            trailing: localRoot == null
                ? const TideChevron()
                : _RowAction(
                    icon: Icons.edit_outlined,
                    onTap: () => _pickLocalRoot(context, ref),
                  ),
            onTap: () async {
              if (localRoot == null) {
                await _pickLocalRoot(context, ref);
                return;
              }
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const SourceBrowseScreen(sourceId: LocalSource.sourceId),
                ),
              );
            },
          ),
        ),
        if (extensions.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: _EmptyNote('No other sources installed.'),
          ),
        if (pinned.isNotEmpty) ...[
          const TideSectionHeader(
            label: 'Pinned',
            padding: EdgeInsets.fromLTRB(20, 26, 20, 12),
          ),
          _rows(pinned, pinnedIds, sourcePrefs),
          const TideSectionHeader(
            label: 'All',
            padding: EdgeInsets.fromLTRB(20, 26, 20, 12),
          ),
        ],
        if (unpinned.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: pinned.isEmpty ? 10 : 0),
            child: _rows(unpinned, pinnedIds, sourcePrefs),
          ),
        if (filtered)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: _EmptyNote('Some sources are hidden by your filter.'),
          ),
      ],
    );
  }

  Widget _rows(
    List<InstalledExtension> extensions,
    Set<String> pinnedIds,
    SourcePreferences? sourcePrefs,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, e) in extensions.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _SourceRow(
              extension: e,
              pinned: pinnedIds.contains(e.id),
              sourcePrefs: sourcePrefs,
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _pickLocalRoot(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Choose your local manga folder',
  );
  if (picked == null) return;
  final prefs = await ref.read(localSourcePreferencesProvider.future);
  await prefs.setRoot(picked);
  // Bust the FutureProvider cache so the row re-reads the new root.
  ref.invalidate(localSourcePreferencesProvider);
  if (!context.mounted) return;
  TideToast.of(context).show('Local folder set to $picked');
}

/// Single row in the Sources list. The pin flips `pinned_catalogues`
/// membership; pinned rows render above the rest under a "Pinned" header.
class _SourceRow extends ConsumerStatefulWidget {
  const _SourceRow({
    required this.extension,
    required this.pinned,
    required this.sourcePrefs,
  });

  final InstalledExtension extension;
  final bool pinned;
  final SourcePreferences? sourcePrefs;

  @override
  ConsumerState<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends ConsumerState<_SourceRow> {
  /// Whether this extension declares the optional `preferences()` contract
  /// — gates the per-source settings gear (Kotlin only shows the gear for
  /// ConfigurableSource implementations too).
  late bool _hasPrefs =
      sourcePrefsCapabilityCache[widget.extension.id] ?? false;

  @override
  void initState() {
    super.initState();
    if (!sourcePrefsCapabilityCache.containsKey(widget.extension.id)) {
      _probePrefs();
    }
  }

  Future<void> _probePrefs() async {
    final id = widget.extension.id;
    try {
      final source = await ref.read(extensionRepositoryProvider).getSource(id);
      final defs = await source.getPreferences();
      sourcePrefsCapabilityCache[id] = defs.isNotEmpty;
      if (mounted && defs.isNotEmpty) setState(() => _hasPrefs = true);
    } catch (_) {
      // Broken extension — no gear; don't cache so a fixed install retries.
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = widget.extension;
    final pinned = widget.pinned;
    final sourcePrefs = widget.sourcePrefs;
    final host = tideSourceHost(extension.baseUrl);
    return _LogoRow(
      seed: extension.id,
      title: extension.name,
      subtitle: [extension.lang.toUpperCase(), ?host].join(' · '),
      baseUrl: extension.baseUrl,
      userAgent: extension.userAgent,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceBrowseScreen(sourceId: extension.id),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasPrefs)
            _RowAction(
              icon: Icons.settings_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourcePreferencesScreen(
                    sourceId: extension.id,
                    sourceName: extension.name,
                  ),
                ),
              ),
            ),
          if (sourcePrefs != null)
            _RowAction(
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              lit: pinned,
              onTap: () => sourcePrefs.toggleSourcePin(extension.id),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------

class _ExtensionsView extends ConsumerStatefulWidget {
  const _ExtensionsView();

  @override
  ConsumerState<_ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends ConsumerState<_ExtensionsView> {
  @override
  void initState() {
    super.initState();
    // Probe origins for newer version_codes once per session — the JS
    // model's stand-in for Kotlin's periodic ExtensionUpdateJob. Drives
    // the Browse nav badge + the per-row "Update available" affordance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runExtensionUpdateCheck(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(extensionRepositoryProvider);
    final updatable = ref.watch(extensionUpdatesProvider);
    final incognitoExtensions = ref.watch(incognitoExtensionsProvider);
    return StreamBuilder<List<InstalledExtension>>(
      stream: repo.watchInstalled(),
      builder: (context, snap) {
        if (snap.hasError) return _LoadFailed(snap.error);
        if (!snap.hasData) return const _Spinner();
        final extensions = snap.data!;
        // Anything with an update waiting is lifted into its own section at
        // the top. Being `lit` in place was easy to miss in a list of
        // twenty-five: the one thing on this screen you can act on should not
        // need finding.
        final pending =
            extensions.where((e) => updatable.contains(e.id)).toList();
        final settled =
            extensions.where((e) => !updatable.contains(e.id)).toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: tideBarInset),
          children: [
            // The install affordance is a row rather than a floating button:
            // a FAB would sit on top of the shell's own navigation bar, and
            // "add one" belongs at the head of the list it adds to.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TideRow(
                icon: Icons.add,
                title: 'Install extension',
                subtitle: 'From a raw .js URL, or a file on this device',
                lit: true,
                trailing: const TideChevron(),
                onTap: () => _showAddSheet(context, repo),
              ),
            ),
            if (extensions.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: _EmptyNote('No extensions installed yet.'),
              )
            else ...[
              if (pending.isNotEmpty) ...[
                TideSectionHeader(
                  label: 'Update available',
                  trailing: '${pending.length}',
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
                ),
                _ExtensionGroup(
                  extensions: pending,
                  updatable: updatable,
                  incognitoExtensions: incognitoExtensions,
                  repo: repo,
                ),
              ],
              TideSectionHeader(
                label: 'Installed',
                trailing: '${settled.length}',
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
              ),
              _ExtensionGroup(
                extensions: settled,
                updatable: updatable,
                incognitoExtensions: incognitoExtensions,
                repo: repo,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A run of extension rows under one section header.
class _ExtensionGroup extends StatelessWidget {
  const _ExtensionGroup({
    required this.extensions,
    required this.updatable,
    required this.incognitoExtensions,
    required this.repo,
  });

  final List<InstalledExtension> extensions;
  final Set<String> updatable;
  final Set<String> incognitoExtensions;
  final ExtensionRepository repo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, e) in extensions.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _ExtensionRow(
              extension: e,
              hasUpdate: updatable.contains(e.id),
              incognito: incognitoExtensions.contains(e.id),
              repo: repo,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExtensionRow extends ConsumerWidget {
  const _ExtensionRow({
    required this.extension,
    required this.hasUpdate,
    required this.incognito,
    required this.repo,
  });

  final InstalledExtension extension;
  final bool hasUpdate;
  final bool incognito;
  final ExtensionRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUpdate = extension.installUrl != null;
    final host = tideSourceHost(extension.baseUrl);
    return _LogoRow(
      seed: extension.id,
      title: extension.name,
      subtitle: '',
      // Language and version are two facts, not one sentence, so they are two
      // tags. The host stays plain text behind them: it identifies the row
      // when the logo fails to resolve, but nobody scans a list for it.
      subtitleChild: Row(
        children: [
          _MetaTag(extension.lang.toUpperCase()),
          const SizedBox(width: 5),
          _MetaTag('v${extension.versionCode}'),
          if (host != null) ...[
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TideText.caption(size: 11, opacity: 0.36),
              ),
            ),
          ],
        ],
      ),
      baseUrl: extension.baseUrl,
      userAgent: extension.userAgent,
      // A row with an update waiting is the one row on this screen worth
      // finding at a glance.
      lit: hasUpdate,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RowAction(
            // One icon, both states. This used to be a ternary whose two
            // branches were the same constant — the `lit` flag was already
            // carrying the state, and the conditional only looked like it
            // meant something.
            icon: Icons.no_encryption_gmailerrorred_outlined,
            lit: incognito,
            // Verbatim Mihon string pref_incognito_mode_extension_summary.
            onTap: () {
              final current = ref.read(incognitoExtensionsProvider);
              final next = {...current};
              if (incognito) {
                next.remove(extension.id);
              } else {
                next.add(extension.id);
              }
              ref.read(incognitoExtensionsProvider.notifier).set(next);
            },
          ),
          if (canUpdate)
            _RowAction(
              icon: Icons.refresh,
              lit: hasUpdate,
              onTap: () async {
                await _runUpdate(context, repo, extension);
                clearExtensionUpdate(ref, extension.id);
              },
            ),
          _RowAction(
            icon: Icons.delete_outlined,
            onTap: () async {
              await _confirmUninstall(context, repo, extension);
              clearExtensionUpdate(ref, extension.id);
            },
          ),
        ],
      ),
    );
  }
}

/// Re-fetches the JS from [e.installUrl] and reinstalls. Surfaces
/// success/failure via [TideToast] so the user gets feedback either way.
/// Compares the manifest version code before/after to tell "Updated"
/// vs "Already up to date" — matches Mihon's update flow wording.
Future<void> _runUpdate(
  BuildContext context,
  ExtensionRepository repo,
  InstalledExtension e,
) async {
  _showProgress(context);
  try {
    final beforeVersion = e.versionCode;
    final updated = await repo.updateFromOrigin(e);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    final unchanged = updated.versionCode == beforeVersion;
    TideToast.of(context).show(
      unchanged
          ? '${updated.name} is already up to date.'
          : 'Updated ${updated.name} '
              '(v$beforeVersion → v${updated.versionCode}).',
    );
  } catch (err) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    TideToast.of(context)
        .show(userMessage(err, fallback: 'Couldn\'t update that extension.'));
  }
}

Future<void> _confirmUninstall(
  BuildContext context,
  ExtensionRepository repo,
  InstalledExtension e,
) async {
  final confirmed = await showTideSheet<bool>(
    context,
    (_) => TideConfirmSheet(
      title: 'Uninstall ${e.name}?',
      message: 'The extension and any cached source code will be removed. '
          'Saved manga and history are kept.',
      confirmLabel: 'Uninstall',
    ),
  );
  if (confirmed == true) {
    await repo.uninstall(e.id);
  }
}

Future<void> _showAddSheet(
  BuildContext context,
  ExtensionRepository repo,
) async {
  await showTideSheet<void>(
    context,
    (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TideRow(
              icon: Icons.link,
              title: 'Install from URL',
              subtitle: 'Paste a raw .js URL',
              trailing: const TideChevron(),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _promptForUrl(context, repo);
              },
            ),
            const SizedBox(height: 8),
            TideRow(
              icon: Icons.upload_file_outlined,
              title: 'Install from file',
              subtitle: 'Pick a .js file from device storage',
              trailing: const TideChevron(),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _promptForFile(context, repo);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _promptForUrl(
  BuildContext context,
  ExtensionRepository repo,
) async {
  final url = await showTideSheet<String>(
    context,
    (_) => const TideInputSheet(
      title: 'Install from URL',
      hintText: 'https://...',
      confirmLabel: 'Install',
      keyboardType: TextInputType.url,
    ),
  );
  if (url == null || url.isEmpty) return;
  if (!context.mounted) return;
  await _runInstall(context, () => repo.installFromUrl(url));
}

Future<void> _promptForFile(
  BuildContext context,
  ExtensionRepository repo,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['js'],
  );
  final path = result?.files.singleOrNull?.path;
  if (path == null) return;
  if (!context.mounted) return;
  await _runInstall(context, () => repo.installFromFile(File(path)));
}

Future<void> _runInstall(
  BuildContext context,
  Future<InstalledExtension> Function() install,
) async {
  _showProgress(context);
  try {
    final extension = await install();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    TideToast.of(context).show('Installed ${extension.name}.');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss progress
    TideToast.of(context)
        .show(userMessage(e, fallback: 'Couldn\'t install that extension.'));
  }
}

/// Blocking spinner over a dimmed screen, dismissed by its caller popping.
///
/// `barrierDismissible: false` only stops taps on the scrim — the system back
/// button would still pop it, and the caller's later unconditional pop would
/// then take the Browse screen down with it. [PopScope] closes that hole so
/// the only way out stays the caller's own pop.
void _showProgress(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: TideSpinner(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

/// A glass row led by the source's own logo.
///
/// Every source would otherwise present the same generic glyph, which makes a
/// list of thirty a list you have to read line by line. Each of these sources
/// is a website with a mark of its own, so the row wears it — falling back to
/// [TideSigil] while it resolves and for the sites that publish nothing.
class _LogoRow extends StatelessWidget {
  const _LogoRow({
    required this.seed,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.subtitleChild,
    this.baseUrl,
    this.userAgent,
    this.onTap,
    this.lit = false,
  });

  final String seed;
  final String title;
  final String subtitle;

  /// Replaces [subtitle] when a row has more to say than one line of text —
  /// an extension carries a language, a version and sometimes an update, and
  /// running those together as `EN · v12 · Update available` reads as one
  /// grey string rather than three separate facts.
  final Widget? subtitleChild;

  /// The site whose logo leads the row.
  final String? baseUrl;
  final String? userAgent;

  /// Null on an extension row: managing an extension is what the trailing
  /// controls are for, and the row itself goes nowhere — same as before.
  final VoidCallback? onTap;
  final Widget trailing;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return TideGlass(
      radius: TideRadius.pane,
      tintTop: lit ? 0.13 : 0.075,
      tintBottom: lit ? 0.05 : 0.026,
      highlight: lit ? 0.20 : 0.14,
      border: lit ? 0.20 : 0.09,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(11, 11, 8, 11),
      child: Row(
        children: [
          TideSourceLogo(
            seed: seed,
            label: title,
            baseUrl: baseUrl,
            userAgent: userAgent,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.title(),
                ),
                const SizedBox(height: 3),
                subtitleChild ??
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TideText.caption(
                        opacity: lit ? 0.62 : 0.45,
                      ).copyWith(color: lit ? TideColors.accent : null),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          trailing,
        ],
      ),
    );
  }
}

/// One fact, boxed. Small enough to sit two or three to a line under a row's
/// title without competing with it.
class _MetaTag extends StatelessWidget {
  const _MetaTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(TideRadius.tag),
        border: Border.all(color: TideColors.hairline),
      ),
      child: Text(
        label,
        style: TideText.caption(size: 10, opacity: 0.62)
            .copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

/// Small quiet control at the end of a row.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.onTap,
    this.lit = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 38,
        child: Icon(
          icon,
          size: 17,
          color: lit ? TideColors.accent : TideColors.textAt(0.42),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TideText.caption(size: 12.5, opacity: 0.4),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Center(
        child: TideSpinner(),
      );
}

/// What both Browse views show when the installed-source list cannot be read.
///
/// Plain centred text rather than [TideEmpty]: the glass card is for ABSENCE
/// (no results, nothing scheduled), and this is FAILURE. Without it a stream
/// error left the tab on [_Spinner] forever, saying nothing.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed(this.error);

  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            userMessage(error ?? '',
                fallback: 'Couldn\'t read your installed sources.'),
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
}
