import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/local_source.dart';
import '../../data/source/source_id.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';
import '../migration/migration_search_screen.dart';

/// Browse → Migrate tab. Lists every source the user currently has
/// favourites on, with a count badge, ordered by descending count.
/// Tapping a source opens [MigrateSourceMangaListScreen] which lists
/// that source's favourites; tapping a manga from there pushes the
/// per-manga [MigrationSearchScreen].
///
/// Mirrors Mihon's `MigrateSourceScreen` step (the top-level list of
/// sources before drilling into individual manga).
class MigrateSourceTab extends ConsumerStatefulWidget {
  const MigrateSourceTab({super.key});

  @override
  ConsumerState<MigrateSourceTab> createState() => _MigrateSourceTabState();
}

class _MigrateSourceTabState extends ConsumerState<MigrateSourceTab> {
  Future<_MigrateSourcesData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
      if (sourceId.toString() == LocalSource.sourceId) {
        name = 'Local source';
        installed = true;
      } else {
        final ext = extByInt[sourceId];
        if (ext != null) {
          name = ext.name;
          lang = ext.lang.toUpperCase();
          installed = true;
        } else {
          name = 'Source $sourceId';
          installed = false;
        }
      }
      return _MigrateSourceEntry(
        sourceId: sourceId,
        name: name,
        lang: lang,
        count: entry.value,
        installed: installed,
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load sources: ${snap.error}'),
            ),
          );
        }
        final entries = snap.data?.entries ?? const <_MigrateSourceEntry>[];
        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'You have no favourited manga to migrate. Add manga to '
                'your library first, then come back here to move them '
                'to another source.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return ListTile(
                title: Text(e.name),
                subtitle: e.lang == null && e.installed
                    ? null
                    : Text(
                        e.installed
                            ? e.lang ?? ''
                            : 'Source not installed — install the '
                                'matching extension to migrate from it.',
                      ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${e.count}',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MigrateSourceMangaListScreen(
                        sourceId: e.sourceId,
                        sourceName: e.name,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
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
  });

  final int sourceId;
  final String name;
  final String? lang;
  final int count;
  final bool installed;
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

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(mangaRepositoryProvider)
        .getFavoritesBySource(widget.sourceId);
  }

  Future<void> _refresh() async {
    final next = ref
        .read(mangaRepositoryProvider)
        .getFavoritesBySource(widget.sourceId);
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.sourceName)),
      body: FutureBuilder<List<Manga>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load manga: ${snap.error}'),
              ),
            );
          }
          final mangas = snap.data ?? const <Manga>[];
          if (mangas.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No favourited manga on this source anymore.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: mangas.length,
              itemBuilder: (_, i) {
                final m = mangas[i];
                return ListTile(
                  leading: SizedBox(
                    width: 40,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: m.thumbnailUrl == null || m.thumbnailUrl!.isEmpty
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(
                                Icons.menu_book,
                                size: 20,
                              ),
                            )
                          : SourceImage(
                              url: m.thumbnailUrl!,
                              errorWidget: (_, _) => Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  size: 20,
                                ),
                              ),
                            ),
                    ),
                  ),
                  title: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: m.author == null || m.author!.isEmpty
                      ? null
                      : Text(
                          m.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MigrationSearchScreen(sourceManga: m),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
