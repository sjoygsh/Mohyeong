import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tide/tide.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/migration/migration_service.dart';
import '../../data/migration/smart_search_engine.dart';
import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/local_source.dart';
import '../../data/source/source_preferences.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/source/model/manga_source.dart';
import '../../domain/source/model/source_manga.dart';
import 'migration_config_screen.dart';
import 'migration_search_screen.dart';

/// Batch migration screen — port of Mihon's `MigrationListScreen`.
///
/// For every selected manga it runs a smart search across the chosen target
/// sources (in order), inserting + chapter-syncing the best match so chapter
/// counts are available for the "hide without updates" / "prioritize by
/// chapters" rules. The user reviews the matches, can re-pick any entry
/// manually, then taps Copy (keep the originals) or Migrate (replace them).
class MigrationListScreen extends ConsumerStatefulWidget {
  const MigrationListScreen({
    super.key,
    required this.mangas,
    required this.config,
  });

  final List<Manga> mangas;
  final MigrationRunConfig config;

  @override
  ConsumerState<MigrationListScreen> createState() =>
      _MigrationListScreenState();
}

enum _Status { searching, found, notFound }

class _Item {
  _Item({
    required this.manga,
    required this.sourceChapterCount,
    required this.sourceLatestChapter,
  });

  final Manga manga;
  final int sourceChapterCount;
  final double? sourceLatestChapter;

  _Status status = _Status.searching;
  Manga? target;
  int targetChapterCount = 0;
  double? targetLatestChapter;
}

class _MigrationListScreenState extends ConsumerState<MigrationListScreen> {
  final List<_Item> _items = [];
  bool _initialized = false;

  late bool _hideUnmatched;
  late bool _hideWithoutUpdates;
  late bool _deepSearch;
  late bool _prioritizeByChapters;
  List<int> _targetSourceIds = const <int>[];

  bool get _searching => _items.any((i) => i.status == _Status.searching);
  bool get _anyFound => _items.any((i) => i.status == _Status.found);
  int get _finished =>
      _items.where((i) => i.status != _Status.searching).length;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final prefs = await ref.read(sourcePreferencesProvider.future);
    _hideUnmatched = prefs.getMigrationHideUnmatched();
    _hideWithoutUpdates = prefs.getMigrationHideWithoutUpdates();
    _deepSearch = prefs.getMigrationDeepSearch();
    _prioritizeByChapters = prefs.getMigrationPrioritizeByChapters();
    _targetSourceIds = prefs.getMigrationSources();

    final chapterRepo = ref.read(chapterRepositoryProvider);
    for (final manga in widget.mangas) {
      final chapters = await chapterRepo.getByMangaId(manga.id);
      _items.add(
        _Item(
          manga: manga,
          sourceChapterCount: chapters.length,
          sourceLatestChapter: chapters.isEmpty
              ? null
              : chapters.map((c) => c.chapterNumber).reduce((a, b) => a > b ? a : b),
        ),
      );
    }
    setState(() => _initialized = true);

    // Resolve the target source instances once, pairing each with the numeric
    // id it was selected by (the source object's own id may be a slug).
    final extRepo = ref.read(extensionRepositoryProvider);
    final sources = <_TargetSource>[];
    for (final id in _targetSourceIds) {
      try {
        sources.add(_TargetSource(id, await extRepo.getSource(id.toString())));
      } catch (_) {
        // Source not installed / failed to load — skip it.
      }
    }

    for (final item in List<_Item>.of(_items)) {
      if (!mounted) return;
      // The item may have been removed (hide rules) while we awaited.
      if (!_items.contains(item)) continue;
      await _searchFor(item, sources);
    }
  }

  Future<void> _searchFor(_Item item, List<_TargetSource> sources) async {
    final engine = SmartSearchEngine(
      extraSearchParams: widget.config.extraSearchQuery,
    );

    _SearchHit? best;
    if (_prioritizeByChapters) {
      _SearchHit? maxHit;
      for (final ts in sources) {
        final hit = await _searchOneSource(engine, item, ts);
        if (hit == null || hit.chapterCount == 0) continue;
        if (maxHit == null ||
            (hit.latestChapter ?? 0) > (maxHit.latestChapter ?? 0)) {
          maxHit = hit;
        }
      }
      best = maxHit;
    } else {
      for (final ts in sources) {
        final hit = await _searchOneSource(engine, item, ts);
        if (hit != null) {
          best = hit;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      if (best == null) {
        item.status = _Status.notFound;
      } else {
        item.status = _Status.found;
        item.target = best.target;
        item.targetChapterCount = best.chapterCount;
        item.targetLatestChapter = best.latestChapter;
      }
    });

    // Apply the hide rules after the result lands.
    if (best == null && _hideUnmatched) {
      _remove(item);
    } else if (best != null &&
        _hideWithoutUpdates &&
        (best.latestChapter ?? 0) <= (item.sourceLatestChapter ?? 0)) {
      _remove(item);
    }
  }

  Future<_SearchHit?> _searchOneSource(
    SmartSearchEngine engine,
    _Item item,
    _TargetSource ts,
  ) async {
    try {
      final source = ts.source;
      final sourceId = ts.numericId;
      final candidate = _deepSearch
          ? await engine.deepSearch(source, item.manga.title)
          : await engine.regularSearch(source, item.manga.title);
      if (candidate == null) return null;
      // Same entry as the original — not a useful migration target.
      if (candidate.url == item.manga.url && sourceId == item.manga.source) {
        return null;
      }

      final mangaRepo = ref.read(mangaRepositoryProvider);
      final target = await mangaRepo.insertFromSource(
        candidate: candidate,
        sourceId: sourceId,
      );

      // Fetch + persist the target's chapters so we know its chapter info.
      try {
        final fetched = await source.fetchChapterList(
          SourceManga(url: target.url, title: target.title),
        );
        await ref.read(chapterRepositoryProvider).syncChaptersWithSource(
              target.id,
              fetched,
              isLocalSource: sourceId == LocalSource.numericId,
            );
      } catch (_) {
        // Chapter fetch failure shouldn't drop the match entirely.
      }

      final chapters =
          await ref.read(chapterRepositoryProvider).getByMangaId(target.id);
      return _SearchHit(
        target: target,
        chapterCount: chapters.length,
        latestChapter: chapters.isEmpty
            ? null
            : chapters.map((c) => c.chapterNumber).reduce((a, b) => a > b ? a : b),
      );
    } catch (_) {
      return null;
    }
  }

  void _remove(_Item item) {
    if (!mounted) return;
    setState(() => _items.remove(item));
    if (_items.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickManually(_Item item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MigrationSearchScreen(sourceManga: item.manga),
      ),
    );
    // The manual screen performs its own migration + pops; once the user is
    // back, drop the handled entry from the batch.
    final refreshed = await ref
        .read(mangaRepositoryProvider)
        .getById(item.manga.id);
    if (refreshed != null && !refreshed.favorite) {
      _remove(item);
    }
  }

  Future<void> _migrateAll({required bool replace}) async {
    final found = _items.where((i) => i.status == _Status.found).toList();
    if (found.isEmpty) return;
    final service = ref.read(migrationServiceProvider);
    final navigator = Navigator.of(context);

    var done = 0;
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progress: progress),
    );

    for (final item in found) {
      try {
        await service.migrate(
          source: item.manga,
          target: item.target!,
          options: MigrationOptions(
            copyChapters: widget.config.copyChapters,
            copyCategories: widget.config.copyCategories,
            copyTracks: true,
            deleteSourceManga: replace,
          ),
        );
      } catch (_) {
        // Continue migrating the rest even if one fails.
      }
      done++;
      progress.value = done / found.length;
    }

    progress.dispose();
    if (!mounted) return;
    navigator.pop(); // progress dialog
    navigator.pop(); // migration list screen
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TideHeader(
            title: 'Review matches',
            subtitle: _searching
                ? 'Searching $_finished of ${_items.length}'
                : null,
          ),
          Expanded(child: !_initialized
          ? const Center(
              child: CircularProgressIndicator(color: TideColors.accent),
            )
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'No entries to migrate.',
                    style: TideText.body(),
                  ),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _ItemTile(
                    item: _items[i],
                    onTap: () => _pickManually(_items[i]),
                  ),
                )),
          if (_initialized && _items.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Opacity(
                        opacity: _searching || !_anyFound ? 0.4 : 1,
                        child: TideButton(
                          label: 'Copy',
                          onTap: () {
                            if (_searching || !_anyFound) return;
                            _migrateAll(replace: false);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Opacity(
                        opacity: _searching || !_anyFound ? 0.4 : 1,
                        child: TideButton(
                          label: 'Migrate',
                          primary: true,
                          onTap: () {
                            if (_searching || !_anyFound) return;
                            _migrateAll(replace: true);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TargetSource {
  const _TargetSource(this.numericId, this.source);

  final int numericId;
  final MangaSource source;
}

class _SearchHit {
  const _SearchHit({
    required this.target,
    required this.chapterCount,
    required this.latestChapter,
  });

  final Manga target;
  final int chapterCount;
  final double? latestChapter;
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});

  final _Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget trailing;
    switch (item.status) {
      case _Status.searching:
        trailing = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _Status.notFound:
        trailing = Text(
          'No match',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      case _Status.found:
        trailing = Text('${item.targetChapterCount} ch');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TideGlass(
        radius: 16,
        onTap: item.status == _Status.searching ? null : onTap,
        padding: const EdgeInsets.fromLTRB(11, 11, 14, 11),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TideCover(manga: item.manga, cacheWidth: 360),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TideText.title(),
                  ),
                  if (item.status == _Status.found && item.target != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '→ ${item.target!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TideText.caption()
                          .copyWith(color: TideColors.accent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress});

  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: TideGlass(
        radius: 26,
        blur: true,
        tintTop: 0.13,
        tintBottom: 0.05,
        highlight: 0.26,
        border: 0.15,
        saturation: 1.9,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Migrating', style: TideText.display(20)),
              const SizedBox(height: 14),
              SizedBox(
                height: 3,
                child: value == 0
                    ? const LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        color: TideColors.accent,
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: (value.clamp(0.0, 1.0) * 1000).round(),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: TideColors.accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: TideColors.accent
                                        .withValues(alpha: 0.75),
                                    blurRadius: 9,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: ((1 - value.clamp(0.0, 1.0)) * 1000).round(),
                            child: const SizedBox.shrink(),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(value * 100).round()}%',
                style: TideText.caption(size: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
