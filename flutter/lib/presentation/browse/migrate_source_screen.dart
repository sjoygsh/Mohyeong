// ===========================================================================
// Tide migrate.
//
// Migration starts from a question — which source are you leaving — so the
// list is ordered by how much you have on each, and each row states the count
// plainly. A source whose extension is gone still holds favourites and still
// has to be listed; it just cannot be migrated FROM until the extension is
// back, so it says so instead of failing on tap.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/local_source.dart';
import '../../data/source/source_id.dart';
import '../../domain/manga/model/manga.dart';
import '../migration/migration_config_screen.dart';
import '../migration/migration_search_screen.dart';
import '../tide/tide.dart';
import '../util/user_message.dart';

/// Browse → Migrate view. Lists every source the user currently has
/// favourites on, with a count, ordered by descending count. Tapping a source
/// opens [MigrateSourceMangaListScreen] which lists that source's favourites;
/// tapping a manga from there pushes the per-manga [MigrationSearchScreen].
///
/// Mirrors Mihon's `MigrateSourceScreen` step (the top-level list of sources
/// before drilling into individual manga).
class MigrateSourceTab extends ConsumerStatefulWidget {
  const MigrateSourceTab({super.key});

  @override
  ConsumerState<MigrateSourceTab> createState() => _MigrateSourceTabState();
}

enum _SortMode { alphabetical, count }

class _MigrateSourceTabState extends ConsumerState<MigrateSourceTab> {
  Future<_MigrateSourcesData>? _future;

  // Mirrors Kotlin MigrateSourceScreen's sticky-header sort controls.
  // Default is most-favourites-first, matching the prior implicit order.
  _SortMode _sortMode = _SortMode.count;
  bool _ascending = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  List<_MigrateSourceEntry> _sorted(List<_MigrateSourceEntry> entries) {
    final sorted = [...entries];
    sorted.sort((a, b) {
      final cmp = _sortMode == _SortMode.alphabetical
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.count.compareTo(b.count);
      return _ascending ? cmp : -cmp;
    });
    return sorted;
  }

  Future<_MigrateSourcesData> _load() async {
    final mangaRepo = ref.read(mangaRepositoryProvider);
    final extRepo = ref.read(extensionRepositoryProvider);
    final results = await Future.wait<Object>([
      mangaRepo.getFavoritesGroupedBySource(),
      extRepo.listInstalled(),
    ]);
    final counts = results[0] as Map<int, int>;
    final exts = results[1] as List<InstalledExtension>;
    final extByInt = <int, InstalledExtension>{
      for (final e in exts) sourceNumericId(e.id): e,
    };
    final entries = counts.entries.map((entry) {
      final sourceId = entry.key;
      String name;
      String? lang;
      bool installed;
      String? extensionId;
      String? baseUrl;
      String? userAgent;
      if (sourceId.toString() == LocalSource.sourceId) {
        name = 'Local source';
        installed = true;
      } else {
        final ext = extByInt[sourceId];
        if (ext != null) {
          name = ext.name;
          lang = ext.lang.toUpperCase();
          installed = true;
          extensionId = ext.id;
          baseUrl = ext.baseUrl;
          userAgent = ext.userAgent;
        } else {
          // The extension is gone, so there is no name to show — an id
          // would only look like a fault.
          name = 'Unknown source';
          installed = false;
        }
      }
      return _MigrateSourceEntry(
        sourceId: sourceId,
        name: name,
        lang: lang,
        count: entry.value,
        installed: installed,
        extensionId: extensionId,
        baseUrl: baseUrl,
        userAgent: userAgent,
      );
    }).toList(growable: false);
    return _MigrateSourcesData(entries);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MigrateSourcesData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: TideSpinner(),
          );
        }
        if (snap.hasError) {
          return _Note(userMessage(snap.error!, fallback: 'Couldn\'t load your sources.'));
        }
        final entries = snap.data?.entries ?? const <_MigrateSourceEntry>[];
        if (entries.isEmpty) {
          return const _Note(
            'You have no favourited manga to migrate. Add manga to your '
            'library first, then come back here to move them to another '
            'source.',
          );
        }
        final sorted = _sorted(entries);
        return Column(
          children: [
            _SortHeader(
              sortMode: _sortMode,
              ascending: _ascending,
              onToggleMode: () => setState(() {
                _sortMode = _sortMode == _SortMode.alphabetical
                    ? _SortMode.count
                    : _SortMode.alphabetical;
              }),
              onToggleDirection: () =>
                  setState(() => _ascending = !_ascending),
            ),
            Expanded(
              child: TideRefresh(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, tideBarInset),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final e = sorted[i];
                    final host = tideSourceHost(e.baseUrl);
                    final facts = [?e.lang, ?host].join(' · ');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TideRow(
                        icon: e.installed
                            ? Icons.swap_horiz
                            : Icons.extension_off_outlined,
                        leading: e.extensionId == null
                            ? null
                            : TideSourceLogo(
                                seed: e.extensionId!,
                                label: e.name,
                                baseUrl: e.baseUrl,
                                userAgent: e.userAgent,
                                size: 36,
                              ),
                        title: e.name,
                        subtitle: !e.installed
                            ? 'Extension not installed — reinstall it to '
                                'migrate from this source.'
                            : facts.isEmpty
                                ? null
                                : facts,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CountPill(count: e.count),
                            const SizedBox(width: 8),
                            const TideChevron(),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MigrateSourceMangaListScreen(
                              sourceId: e.sourceId,
                              sourceName: e.name,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// How many favourites sit on a source — the number the whole ordering is
/// about, so it gets a shape of its own rather than a trailing word.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TideRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Text(
        '$count',
        style: TideText.title(size: 12.5, color: TideColors.textAt(0.8)),
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.sortMode,
    required this.ascending,
    required this.onToggleMode,
    required this.onToggleDirection,
  });

  final _SortMode sortMode;
  final bool ascending;
  final VoidCallback onToggleMode;
  final VoidCallback onToggleDirection;

  @override
  Widget build(BuildContext context) {
    final alpha = sortMode == _SortMode.alphabetical;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Migrate from',
              style: TideText.kicker(size: 13, color: TideColors.textAt(0.5))
                  .copyWith(letterSpacing: 1.82),
            ),
          ),
          // The sort controls say what they are DOING, not what tapping them
          // would do — a bare icon pair here read as a puzzle.
          TideChip(
            label: alpha ? 'A–Z' : 'Entries',
            icon: alpha ? Icons.sort_by_alpha : Icons.numbers,
            selected: false,
            onTap: onToggleMode,
          ),
          const SizedBox(width: 8),
          TideIconButton(
            icon: ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 32,
            iconSize: 15,
            onTap: onToggleDirection,
          ),
        ],
      ),
    );
  }
}

class _MigrateSourcesData {
  const _MigrateSourcesData(this.entries);

  final List<_MigrateSourceEntry> entries;
}

class _MigrateSourceEntry {
  const _MigrateSourceEntry({
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.count,
    required this.installed,
    this.extensionId,
    this.baseUrl,
    this.userAgent,
  });

  final int sourceId;
  final String name;
  final String? lang;
  final int count;
  final bool installed;

  /// Present only while the extension is still installed — the manifest is
  /// where the site (and so its logo) comes from. A source whose extension is
  /// gone still holds favourites, and still gets listed, wearing a glyph.
  final String? extensionId;
  final String? baseUrl;
  final String? userAgent;
}

/// Lists every favourited manga that belongs to [sourceId]. Tapping a
/// row hands off to the existing [MigrationSearchScreen] which performs
/// the actual per-manga source-to-source migration.
class MigrateSourceMangaListScreen extends ConsumerStatefulWidget {
  const MigrateSourceMangaListScreen({
    super.key,
    required this.sourceId,
    required this.sourceName,
  });

  final int sourceId;
  final String sourceName;

  @override
  ConsumerState<MigrateSourceMangaListScreen> createState() =>
      _MigrateSourceMangaListScreenState();
}

class _MigrateSourceMangaListScreenState
    extends ConsumerState<MigrateSourceMangaListScreen> {
  Future<List<Manga>>? _future;

  // Multi-select for batch migration. Long-press enters selection mode;
  // tapping then toggles. The Continue bar hands the selection off to
  // MigrationConfigScreen. Mirrors Mihon's MigrateMangaScreen selection.
  final Set<int> _selected = <int>{};
  List<Manga> _lastLoaded = const <Manga>[];

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(mangaRepositoryProvider).getFavoritesBySource(widget.sourceId);
  }

  Future<void> _refresh() async {
    final next =
        ref.read(mangaRepositoryProvider).getFavoritesBySource(widget.sourceId);
    setState(() => _future = next);
    await next;
  }

  void _toggleSelection(Manga m) {
    setState(() {
      if (!_selected.add(m.id)) _selected.remove(m.id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _continue() {
    final chosen = _lastLoaded.where((m) => _selected.contains(m.id)).toList();
    if (chosen.isEmpty) return;
    _clearSelection();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MigrationConfigScreen(mangas: chosen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      // Back out of selection before backing out of the screen — otherwise
      // the only way to drop a selection is to undo every tap.
      body: PopScope(
        canPop: !_selectionMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _clearSelection();
        },
        child: TideRise(
          child: Stack(
            children: [
              const Positioned.fill(
                child: TideAurora(opacity: TideAuroraLevel.dense),
              ),
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TideHeader(
                      title: _selectionMode
                          ? '${_selected.length} selected'
                          : widget.sourceName,
                      onBack: _selectionMode ? _clearSelection : null,
                    ),
                    Expanded(child: _body()),
                  ],
                ),
              ),
              if (_selectionMode)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _ContinueBar(
                    count: _selected.length,
                    onTap: _continue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<List<Manga>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: TideSpinner(),
          );
        }
        if (snap.hasError) {
          return _Note(userMessage(snap.error!, fallback: 'Couldn\'t load those entries.'));
        }
        final mangas = snap.data ?? const <Manga>[];
        _lastLoaded = mangas;
        if (mangas.isEmpty) {
          return const _Note('No favourited manga on this source anymore.');
        }
        return TideRefresh(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 2, 16, _selectionMode ? 104 : 28),
            itemCount: mangas.length,
            itemBuilder: (_, i) {
              final m = mangas[i];
              final selected = _selected.contains(m.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TideGlass(
                  radius: TideRadius.pane,
                  tintTop: selected ? 0.15 : 0.075,
                  tintBottom: selected ? 0.05 : 0.026,
                  highlight: selected ? 0.20 : 0.14,
                  border: selected ? 0.28 : 0.09,
                  padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(m);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MigrationSearchScreen(sourceManga: m),
                      ),
                    );
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPress: () => _toggleSelection(m),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 58,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(TideRadius.chip),
                            child: TideCover(manga: m, cacheWidth: 240),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                m.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TideText.title(),
                              ),
                              if (m.author != null && m.author!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  m.author!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TideText.caption(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_selectionMode) ...[
                          const SizedBox(width: 10),
                          _SelectMark(selected: selected),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: tideEase,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected
            ? TideColors.accent
            : Colors.white.withValues(alpha: 0.06),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? TideColors.accent
              : Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: TideColors.ground)
          : null,
    );
  }
}

/// Hands the selection to the migration config step. Same shape as the series
/// screen's Continue bar — a persistent action that follows you down the list.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.count, required this.onTap});

  final int count;
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MIGRATE',
                    style: TideText.kicker(
                      size: 10,
                      color: TideColors.textAt(0.5),
                    ).copyWith(letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    count == 1 ? '1 entry' : '$count entries',
                    style: TideText.title(size: 15)
                        .copyWith(color: TideColors.textBright),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
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

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
}
