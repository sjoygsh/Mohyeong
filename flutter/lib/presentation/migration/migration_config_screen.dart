import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';

import '../settings/pref_tiles.dart';

import '../../data/source/extension_repository.dart';
import '../../data/source/local_source.dart';
import '../../data/source/source_id.dart';
import '../../data/source/source_preferences.dart';
import '../../domain/manga/model/manga.dart';
import 'migration_list_screen.dart';
import 'migration_search_screen.dart';

/// Source-selection step of a batch migration.
///
/// Port of Mihon's `MigrationConfigScreen`. The user picks (and orders) the
/// target sources the smart-search should sweep, then taps Continue. A single
/// selected manga skips straight to the per-manga [MigrationSearchScreen]
/// (matching Kotlin's `continueMigration` single-id branch); multiple manga
/// open a "Data to migrate" sheet and then the batch [MigrationListScreen].
///
/// Sources split into a reorderable "Selected" list and an "Available" list.
/// The chosen set + order persist to `SourcePreferences.migrationSources` so
/// the next migration starts where this one left off.
class MigrationConfigScreen extends ConsumerStatefulWidget {
  const MigrationConfigScreen({super.key, required this.mangas});

  final List<Manga> mangas;

  @override
  ConsumerState<MigrationConfigScreen> createState() =>
      _MigrationConfigScreenState();
}

enum _SelectionConfig { all, none, pinned, enabled }

class _MigSource {
  _MigSource({
    required this.slug,
    required this.numericId,
    required this.name,
    required this.lang,
    required this.isSelected,
  });

  final String slug;
  final int numericId;
  final String name;
  final String lang;
  bool isSelected;

  String get shortLanguage => lang.toUpperCase();
}

class _MigrationConfigScreenState extends ConsumerState<MigrationConfigScreen> {
  List<_MigSource>? _sources;
  SourcePreferences? _prefs;
  bool _showLanguage = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await ref.read(sourcePreferencesProvider.future);
    final installed = await ref.read(extensionRepositoryProvider).listInstalled();

    final languages = prefs.getEnabledLanguages();
    final pinned = prefs.getPinnedSources();
    final disabled = prefs.getDisabledSources();
    final included = prefs.getMigrationSources();

    final sources = installed
        // Local source isn't an HttpSource in Mihon, so it's excluded.
        .where((e) => e.id != LocalSource.sourceId)
        .where((e) => languages.contains(e.lang))
        .map((e) {
      final numericId = sourceNumericId(e.id);
      final bool selected;
      if (included.isNotEmpty) {
        selected = included.contains(numericId);
      } else if (pinned.isNotEmpty) {
        selected = pinned.contains(e.id);
      } else {
        selected = !disabled.contains(e.id);
      }
      return _MigSource(
        slug: e.id,
        numericId: numericId,
        name: e.name,
        lang: e.lang,
        isSelected: selected,
      );
    }).toList();

    final sorted = _sortedWith(sources, included);
    final showLanguage =
        sources.map((s) => s.lang).toSet().length > 1;

    setState(() {
      _prefs = prefs;
      _sources = sorted;
      _showLanguage = showLanguage;
    });
  }

  /// Mihon's `sourcesComparator`: unselected last, then by position in the
  /// included list, then by "name (lang)".
  List<_MigSource> _sortedWith(
    List<_MigSource> sources,
    List<int> includedOrder,
  ) {
    final out = [...sources];
    out.sort((a, b) {
      // Unselected sink to the bottom.
      if (a.isSelected != b.isSelected) return a.isSelected ? -1 : 1;
      final ai = includedOrder.indexOf(a.numericId);
      final bi = includedOrder.indexOf(b.numericId);
      if (ai != bi) return ai.compareTo(bi);
      return '${a.name} (${a.shortLanguage})'
          .compareTo('${b.name} (${b.shortLanguage})');
    });
    return out;
  }

  List<int> get _includedOrder => (_sources ?? const <_MigSource>[])
      .where((s) => s.isSelected)
      .map((s) => s.numericId)
      .toList();

  void _resort() {
    final sources = _sources;
    if (sources == null) return;
    setState(() => _sources = _sortedWith(sources, _includedOrder));
  }

  Future<void> _save() async {
    await _prefs?.setMigrationSources(_includedOrder);
  }

  void _toggle(_MigSource source) {
    source.isSelected = !source.isSelected;
    _resort();
    _save();
  }

  void _applyConfig(_SelectionConfig config) {
    final sources = _sources;
    final prefs = _prefs;
    if (sources == null || prefs == null) return;
    final pinned = prefs.getPinnedSources();
    final disabled = prefs.getDisabledSources();
    for (final s in sources) {
      switch (config) {
        case _SelectionConfig.all:
          s.isSelected = true;
        case _SelectionConfig.none:
          s.isSelected = false;
        case _SelectionConfig.pinned:
          s.isSelected = pinned.contains(s.slug);
        case _SelectionConfig.enabled:
          s.isSelected = !disabled.contains(s.slug);
      }
    }
    _resort();
    _save();
  }

  void _reorderSelected(int oldIndex, int newIndex) {
    final sources = _sources;
    if (sources == null) return;
    final selected = sources.where((s) => s.isSelected).toList();
    if (oldIndex < 0 || oldIndex >= selected.length) return;
    final moved = selected.removeAt(oldIndex);
    selected.insert(newIndex.clamp(0, selected.length), moved);
    final available = sources.where((s) => !s.isSelected).toList();
    setState(() => _sources = [...selected, ...available]);
    _save();
  }

  Future<void> _continue() async {
    await _save();
    if (!mounted) return;
    // Single manga: go straight to the manual per-manga search, matching
    // Mihon's continueMigration single-id branch.
    if (widget.mangas.length == 1) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MigrationSearchScreen(sourceManga: widget.mangas.first),
        ),
      );
      return;
    }
    final config = await showTideSheet<MigrationRunConfig>(
      context,
      (_) => _MigrationConfigSheet(prefs: _prefs!),
    );
    if (config == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MigrationListScreen(
          mangas: widget.mangas,
          config: config,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(children: [
        const Positioned.fill(
          child: TideAurora(opacity: TideAuroraLevel.dense),
        ),
        Positioned.fill(child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TideHeader(
              title: 'Choose sources',
              actions: [
                TideIconButton(
                  icon: Icons.more_horiz,
                  onTap: sources == null ? null : _openSelectionMenu,
                ),
              ],
            ),
            Expanded(child:
      sources == null
          ? const Center(
              child: TideSpinner(),
            )
          : _buildList(sources)),
          ],
        )),
        if (sources != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _ContinueBar(onTap: _continue),
          ),
      ]),
    );
  }

  /// Select-all / none / enabled / pinned, in one sheet — three toolbar
  /// controls for four variants of the same choice was three too many.
  Future<void> _openSelectionMenu() async {
    final picked = await showTideSheet<String>(
      context,
      (_) => const TideOptionSheet(
        title: 'Select sources',
        options: [
          ('all', 'Select all'),
          ('none', 'Select none'),
          ('enabled', 'Select enabled sources'),
          ('pinned', 'Select pinned sources'),
        ],
        selected: '',
      ),
    );
    switch (picked) {
      case 'all':
        _applyConfig(_SelectionConfig.all);
      case 'none':
        _applyConfig(_SelectionConfig.none);
      case 'enabled':
        _applyConfig(_SelectionConfig.enabled);
      case 'pinned':
        _applyConfig(_SelectionConfig.pinned);
    }
  }

  Widget _buildList(List<_MigSource> sources) {
    final selected = sources.where((s) => s.isSelected).toList();
    final available = sources.where((s) => !s.isSelected).toList();

    return CustomScrollView(
      slivers: [
        if (selected.isNotEmpty) ...[
          _header('Selected'),
          SliverReorderableList(
            itemCount: selected.length,
            itemBuilder: (context, i) {
              final s = selected[i];
              return _SourceRow(
                key: ValueKey('selected-${s.numericId}'),
                source: s,
                showLanguage: _showLanguage,
                dragIndex: selected.length > 1 ? i : null,
                onTap: () => _toggle(s),
              );
            },
            onReorderItem: _reorderSelected,
          ),
        ],
        if (available.isNotEmpty) ...[
          _header('Available'),
          SliverList.builder(
            itemCount: available.length,
            itemBuilder: (context, i) {
              final s = available[i];
              return _SourceRow(
                key: ValueKey('available-${s.numericId}'),
                source: s,
                showLanguage: _showLanguage,
                dragIndex: null,
                onTap: () => _toggle(s),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }

  Widget _header(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: Text(text, style: TideText.body()),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.showLanguage,
    required this.dragIndex,
    required this.onTap,
  });

  final _MigSource source;
  final bool showLanguage;
  final int? dragIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PrefRowShell(
      onTap: onTap,
      lit: source.isSelected,
      child: Row(
        children: [
          if (dragIndex != null) ...[
            ReorderableDragStartListener(
              index: dragIndex!,
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: TideColors.textAt(0.32),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TideText.title(),
            ),
          ),
          if (showLanguage) ...[
            const SizedBox(width: 8),
            TideTag(source.shortLanguage),
          ],
        ],
      ),
    );
  }
}

/// What a batch migration should carry over, plus the extra search keywords.
/// Mihon's sheet exposes more flags (custom cover, notes, delete downloads),
/// but the Flutter [MigrationService] only implements chapter / category /
/// tracker copy, so only the honestly-wired axes are surfaced here. Trackers
/// always migrate (Mihon dropped the tracker flag too).
class MigrationRunConfig {
  const MigrationRunConfig({
    this.extraSearchQuery,
    this.copyChapters = true,
    this.copyCategories = true,
  });

  final String? extraSearchQuery;
  final bool copyChapters;
  final bool copyCategories;
}

/// "Data to migrate" + smart-search options sheet. Pops a [MigrationRunConfig]
/// on Continue, and null on dismissal.
class _MigrationConfigSheet extends StatefulWidget {
  const _MigrationConfigSheet({required this.prefs});

  final SourcePreferences prefs;

  @override
  State<_MigrationConfigSheet> createState() => _MigrationConfigSheetState();
}

class _MigrationConfigSheetState extends State<_MigrationConfigSheet> {
  final TextEditingController _queryController = TextEditingController();
  bool _copyChapters = true;
  bool _copyCategories = true;
  late bool _hideUnmatched = widget.prefs.getMigrationHideUnmatched();
  late bool _hideWithoutUpdates = widget.prefs.getMigrationHideWithoutUpdates();
  late bool _deepSearch = widget.prefs.getMigrationDeepSearch();
  late bool _prioritizeByChapters =
      widget.prefs.getMigrationPrioritizeByChapters();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Migrate', style: TideText.display(21)),
              TideSectionHeader(
                label: 'Data to carry over',
                padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
              ),
              Row(
                children: [
                  TideChip(
                    label: 'Chapters',
                    selected: _copyChapters,
                    onTap: () => setState(() => _copyChapters = !_copyChapters),
                  ),
                  const SizedBox(width: 8),
                  TideChip(
                    label: 'Categories',
                    selected: _copyCategories,
                    onTap: () =>
                        setState(() => _copyCategories = !_copyCategories),
                  ),
                ],
              ),
              TideSectionHeader(
                label: 'Search',
                padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
              ),
              TideField(
                controller: _queryController,
                hintText: 'Additional keywords (optional)',
                icon: Icons.search,
              ),
              const SizedBox(height: 12),
              _ConfigSwitch(
                title: 'Hide entries without a match',
                value: _hideUnmatched,
                onChanged: (v) {
                  setState(() => _hideUnmatched = v);
                  widget.prefs.setMigrationHideUnmatched(v);
                },
              ),
              _ConfigSwitch(
                title: 'Hide entries without newer chapters',
                subtitle: 'Only show a match that has additional chapters',
                value: _hideWithoutUpdates,
                onChanged: (v) {
                  setState(() => _hideWithoutUpdates = v);
                  widget.prefs.setMigrationHideWithoutUpdates(v);
                },
              ),
              TideSectionHeader(
                label: 'Slow and risky',
                padding: const EdgeInsets.fromLTRB(2, 24, 2, 8),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                child: Text(
                  'These search every source hard enough that some of them '
                  'will start refusing you.',
                  style: TideText.caption(size: 12.5),
                ),
              ),
              _ConfigSwitch(
                title: 'Advanced search mode',
                subtitle: 'Break the title into keywords for a wider search',
                value: _deepSearch,
                onChanged: (v) {
                  setState(() => _deepSearch = v);
                  widget.prefs.setMigrationDeepSearch(v);
                },
              ),
              _ConfigSwitch(
                title: 'Match on chapter number',
                subtitle: 'Take the match furthest ahead, not the '
                    'highest-priority source',
                value: _prioritizeByChapters,
                onChanged: (v) {
                  setState(() => _prioritizeByChapters = v);
                  widget.prefs.setMigrationPrioritizeByChapters(v);
                },
              ),
              const SizedBox(height: 20),
              TideButton(
                label: 'Continue',
                primary: true,
                onTap: () {
                  final cleaned = _queryController.text.trim();
                  Navigator.of(context).pop(
                    MigrationRunConfig(
                      extraSearchQuery: cleaned.isEmpty ? null : cleaned,
                      copyChapters: _copyChapters,
                      copyCategories: _copyCategories,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A switch on a pane of glass, for the options in the config sheet. The
/// settings screens get this from PrefSwitch; a sheet has no PrefScaffold
/// around it, so it carries its own.
class _ConfigSwitch extends StatelessWidget {
  const _ConfigSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TideGlass(
        radius: TideRadius.row,
        tintTop: value ? 0.115 : 0.06,
        tintBottom: value ? 0.042 : 0.02,
        highlight: value ? 0.18 : 0.12,
        border: value ? 0.17 : 0.08,
        onTap: () => onChanged(!value),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TideText.title(size: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: TideText.caption(size: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            TideSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Hands the picked sources to the next step. Same persistent-action shape
/// the series screen and the download queue use.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TideGlass(
        radius: TideRadius.sheet,
        blur: true,
        tintTop: 0.14,
        tintBottom: 0.05,
        highlight: 0.28,
        border: 0.16,
        saturation: 1.9,
        onTap: onTap,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 44,
            offset: const Offset(0, 18),
          ),
        ],
        padding: const EdgeInsets.fromLTRB(22, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Continue',
                style: TideText.title(size: 15)
                    .copyWith(color: TideColors.textBright),
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TideColors.accent,
                boxShadow: [
                  BoxShadow(
                    color: TideColors.accent.withValues(alpha: 0.55),
                    blurRadius: 26,
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 21,
                color: TideColors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
