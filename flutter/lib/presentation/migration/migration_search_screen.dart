import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/migration/migration_service.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/source_id.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/source/model/source_manga.dart';
import '../common/source_image.dart';
import '../util/user_message.dart';

/// Source-to-source migration screen.
///
/// Flow:
///  1. User picks a target source from the chip strip at the top.
///  2. The search box auto-fills with the source manga's title; the
///     user can refine.
///  3. Results from that source render as a grid.
///  4. Tapping a result opens a confirmation dialog with per-axis
///     toggles. Confirming runs [MigrationService.migrate] and pops
///     back to the new manga's details screen.
///
/// Mirrors Mihon's `MigrateSearchScreen` / `MigrationProcedureScreen`
/// pair — collapsed into one screen here since we don't have Mihon's
/// "queue every source in parallel" UX yet.
class MigrationSearchScreen extends ConsumerStatefulWidget {
  const MigrationSearchScreen({super.key, required this.sourceManga});

  final Manga sourceManga;

  @override
  ConsumerState<MigrationSearchScreen> createState() =>
      _MigrationSearchScreenState();
}

class _MigrationSearchScreenState
    extends ConsumerState<MigrationSearchScreen> {
  late final TextEditingController _queryController =
      TextEditingController(text: widget.sourceManga.title);
  String _activeQuery = '';
  InstalledExtension? _selectedExt;
  Future<List<InstalledExtension>>? _extsFuture;
  Future<List<SourceManga>>? _resultsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _activeQuery = widget.sourceManga.title.trim();
    _extsFuture = ref
        .read(extensionRepositoryProvider)
        .listInstalled()
        .then((all) =>
            // Hide the manga's own source — migrating onto the same
            // source is a no-op for the user's intent.
            all
                .where((e) =>
                    sourceNumericId(e.id) != widget.sourceManga.source)
                .toList(growable: false))
        .then((filtered) {
      if (filtered.isNotEmpty && _selectedExt == null) {
        // Auto-pick the first available source so the user sees results
        // immediately on screen open.
        Future.microtask(() => _onExtensionPicked(filtered.first));
      }
      return filtered;
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _onExtensionPicked(InstalledExtension ext) {
    setState(() {
      _selectedExt = ext;
      _resultsFuture = _runSearch(ext, _activeQuery);
    });
  }

  void _submitQuery() {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _activeQuery = q;
      final ext = _selectedExt;
      if (ext != null) {
        _resultsFuture = _runSearch(ext, q);
      }
    });
  }

  Future<List<SourceManga>> _runSearch(
    InstalledExtension ext,
    String query,
  ) async {
    final src = await ref.read(extensionRepositoryProvider).getSource(ext.id);
    final page = await src.fetchSearch(query, 1);
    return page.mangas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12,
              16,
              10,
            ),
            child: Row(
              children: [
                TideIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 15,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TideGlass(
                      radius: TideRadius.panel,
                      tintTop: 0.09,
                      tintBottom: 0.03,
                      highlight: 0.16,
                      border: 0.11,
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _queryController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _submitQuery(),
                              cursorColor: TideColors.accent,
                              style: TideText.title(size: 14.5),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                hintText: 'Search target source',
                                hintStyle: TideText.title(
                                  size: 14.5,
                                  color: TideColors.textAt(0.33),
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _submitQuery,
                            child: SizedBox(
                              width: 36,
                              height: 42,
                              child: Icon(
                                Icons.search,
                                size: 18,
                                color: TideColors.textAt(0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SourcePickerBar(
            future: _extsFuture,
            selected: _selectedExt,
            onPicked: _onExtensionPicked,
          ),
          Expanded(
            child: _busy
                ? const _MigratingOverlay()
                : _ResultsArea(
                    sourceManga: widget.sourceManga,
                    selectedExt: _selectedExt,
                    resultsFuture: _resultsFuture,
                    onPickTarget: _onPickTarget,
                  ),
          ),
        ],
      ),
        ],
      ),
    );
  }

  Future<void> _onPickTarget(SourceManga candidate) async {
    final ext = _selectedExt;
    if (ext == null) return;
    final toast = TideToast.of(context);
    final options = await showTideSheet<MigrationOptions>(
      context,
      (_) => _MigrationConfirmDialog(
        sourceManga: widget.sourceManga,
        targetSource: ext,
        candidate: candidate,
      ),
    );
    if (options == null) return;
    setState(() => _busy = true);
    try {
      final sourceId = sourceNumericId(ext.id);
      final mangaRepo = ref.read(mangaRepositoryProvider);
      // Find or create the target manga row.
      final target = await mangaRepo.insertFromSource(
        candidate: candidate,
        sourceId: sourceId,
      );
      await ref.read(migrationServiceProvider).migrate(
            source: widget.sourceManga,
            target: target,
            options: options,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      toast.show('Migration complete.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast.show(userMessage(e, fallback: 'Couldn\'t migrate that entry.'));
    }
  }

}

class _SourcePickerBar extends StatelessWidget {
  const _SourcePickerBar({
    required this.future,
    required this.selected,
    required this.onPicked,
  });

  final Future<List<InstalledExtension>>? future;
  final InstalledExtension? selected;
  final ValueChanged<InstalledExtension> onPicked;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InstalledExtension>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(userMessage(snap.error!, fallback: 'Couldn\'t load your sources.')),
          );
        }
        if (!snap.hasData) {
          return const SizedBox(
            height: 56,
            child: Center(child: TideSpinner()),
          );
        }
        final exts = snap.data!;
        if (exts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No other sources installed. Install one from Browse '
              '→ Extensions before migrating.',
              textAlign: TextAlign.center,
            ),
          );
        }
        return SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: exts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final ext = exts[i];
              return Center(
                child: TideChip(
                  label: ext.name,
                  selected: ext.id == selected?.id,
                  onTap: () => onPicked(ext),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ResultsArea extends StatelessWidget {
  const _ResultsArea({
    required this.sourceManga,
    required this.selectedExt,
    required this.resultsFuture,
    required this.onPickTarget,
  });

  final Manga sourceManga;
  final InstalledExtension? selectedExt;
  final Future<List<SourceManga>>? resultsFuture;
  final ValueChanged<SourceManga> onPickTarget;

  @override
  Widget build(BuildContext context) {
    if (selectedExt == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Pick a target source above to start searching.'),
        ),
      );
    }
    return FutureBuilder<List<SourceManga>>(
      future: resultsFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(userMessage(snap.error!, fallback: 'That search failed.')),
          );
        }
        if (!snap.hasData) {
          return const Center(child: TideSpinner());
        }
        final results = snap.data!;
        if (results.isEmpty) {
          return const TideEmpty(
            title: 'No matches',
            message:
                'This source has nothing that looks like the same series.',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            childAspectRatio: 0.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: results.length,
          itemBuilder: (_, i) => _ResultTile(
            manga: results[i],
            onTap: () => onPickTarget(results[i]),
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.manga, required this.onTap});

  final SourceManga manga;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(TideRadius.row),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TideRadius.row),
                child: Builder(
                  builder: (context) {
                    final url = manga.thumbnailUrl;
                    final fallback = DecoratedBox(
                      decoration: BoxDecoration(
                        gradient:
                            TideCover.fallbackGradient(manga.url.hashCode),
                      ),
                    );
                    if (url == null || url.isEmpty) return fallback;
                    return SourceImage(
                      cacheWidth: 360,
                      url: url,
                      fit: BoxFit.cover,
                      placeholder: (_) => fallback,
                      errorWidget: (_, _) => fallback,
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TideText.caption(size: 11.5, opacity: 0.62),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigratingOverlay extends StatelessWidget {
  const _MigratingOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TideSpinner(),
          SizedBox(height: 12),
          Text('Migrating...'),
        ],
      ),
    );
  }
}

class _MigrationConfirmDialog extends StatefulWidget {
  const _MigrationConfirmDialog({
    required this.sourceManga,
    required this.targetSource,
    required this.candidate,
  });

  final Manga sourceManga;
  final InstalledExtension targetSource;
  final SourceManga candidate;

  @override
  State<_MigrationConfirmDialog> createState() =>
      _MigrationConfirmDialogState();
}

class _MigrationConfirmDialogState extends State<_MigrationConfirmDialog> {
  MigrationOptions _options = const MigrationOptions();

  @override
  Widget build(BuildContext context) {
    return TideSheetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Migrate this entry', style: TideText.display(21)),
          const SizedBox(height: 8),
          Text(
            '${widget.sourceManga.title}  →  ${widget.candidate.title} '
            '(${widget.targetSource.name})',
            style: TideText.caption(size: 12.5),
          ),
          const SizedBox(height: 18),
          _OptionTile(
            label: 'Copy chapter read state',
            value: _options.copyChapters,
            onChanged: (v) => setState(
              () => _options = MigrationOptions(
                copyChapters: v,
                copyCategories: _options.copyCategories,
                copyTracks: _options.copyTracks,
                deleteSourceManga: _options.deleteSourceManga,
              ),
            ),
          ),
          _OptionTile(
            label: 'Copy categories',
            value: _options.copyCategories,
            onChanged: (v) => setState(
              () => _options = MigrationOptions(
                copyChapters: _options.copyChapters,
                copyCategories: v,
                copyTracks: _options.copyTracks,
                deleteSourceManga: _options.deleteSourceManga,
              ),
            ),
          ),
          _OptionTile(
            label: 'Copy tracker entries',
            value: _options.copyTracks,
            onChanged: (v) => setState(
              () => _options = MigrationOptions(
                copyChapters: _options.copyChapters,
                copyCategories: _options.copyCategories,
                copyTracks: v,
                deleteSourceManga: _options.deleteSourceManga,
              ),
            ),
          ),
          _OptionTile(
            label: 'Remove old entry from library',
            value: _options.deleteSourceManga,
            onChanged: (v) => setState(
              () => _options = MigrationOptions(
                copyChapters: _options.copyChapters,
                copyCategories: _options.copyCategories,
                copyTracks: _options.copyTracks,
                deleteSourceManga: v,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: TideButton(
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TideButton(
                  label: 'Migrate',
                  primary: true,
                  onTap: () => Navigator.of(context).pop(_options),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TideCheck(label: label, value: value, onChanged: onChanged),
    );
  }
}
