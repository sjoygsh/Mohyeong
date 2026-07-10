import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final config = await showModalBottomSheet<MigrationRunConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MigrationConfigSheet(prefs: _prefs!),
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
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: sources == null
                ? null
                : () => _applyConfig(_SelectionConfig.all),
          ),
          IconButton(
            icon: const Icon(Icons.deselect),
            tooltip: 'Select none',
            onPressed: sources == null
                ? null
                : () => _applyConfig(_SelectionConfig.none),
          ),
          PopupMenuButton<_SelectionConfig>(
            onSelected: _applyConfig,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SelectionConfig.enabled,
                child: Text('Select enabled sources'),
              ),
              PopupMenuItem(
                value: _SelectionConfig.pinned,
                child: Text('Select pinned sources'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: sources == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _continue,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue'),
            ),
      body: sources == null
          ? const Center(child: CircularProgressIndicator())
          : _buildList(sources),
    );
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
        padding: const EdgeInsets.all(16),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
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
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showLanguage)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  source.shortLanguage,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
      trailing: dragIndex == null
          ? null
          : ReorderableDragStartListener(
              index: dragIndex!,
              child: const Icon(Icons.drag_handle),
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Data to migrate',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Chapters'),
                    selected: _copyChapters,
                    onSelected: (v) => setState(() => _copyChapters = v),
                  ),
                  FilterChip(
                    label: const Text('Categories'),
                    selected: _copyCategories,
                    onSelected: (v) => setState(() => _copyCategories = v),
                  ),
                ],
              ),
              const Divider(),
              TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Additional keywords (optional)',
                  helperText:
                      'Helps narrow down search results by adding '
                      'additional keywords',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide entries without a match'),
                value: _hideUnmatched,
                onChanged: (v) {
                  setState(() => _hideUnmatched = v);
                  widget.prefs.setMigrationHideUnmatched(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide entries without newer chapters'),
                subtitle: const Text(
                  'Only show entry if the match has additional chapters',
                ),
                value: _hideWithoutUpdates,
                onChanged: (v) {
                  setState(() => _hideWithoutUpdates = v);
                  widget.prefs.setMigrationHideWithoutUpdates(v);
                },
              ),
              const Divider(),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These options are slow and dangerous and may lead '
                      'to restrictions from sources',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Advanced search mode'),
                subtitle: const Text(
                  'Breaks down the title into keywords for a wider search',
                ),
                value: _deepSearch,
                onChanged: (v) {
                  setState(() => _deepSearch = v);
                  widget.prefs.setMigrationDeepSearch(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Match based on chapter number'),
                subtitle: const Text(
                  'If enabled, chooses the match furthest ahead. Otherwise, '
                  'picks the first match by source priority.',
                ),
                value: _prioritizeByChapters,
                onChanged: (v) {
                  setState(() => _prioritizeByChapters = v);
                  widget.prefs.setMigrationPrioritizeByChapters(v);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final cleaned = _queryController.text.trim();
                  Navigator.of(context).pop(
                    MigrationRunConfig(
                      extraSearchQuery: cleaned.isEmpty ? null : cleaned,
                      copyChapters: _copyChapters,
                      copyCategories: _copyCategories,
                    ),
                  );
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
