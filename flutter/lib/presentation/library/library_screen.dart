import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_updater.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

enum LibrarySort { titleAsc, dateAddedDesc, lastUpdateDesc }

/// Library tab: streams favorites, filters by an in-AppBar search query,
/// and sorts client-side per the selected mode.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  LibrarySort _sort = LibrarySort.titleAsc;
  bool _searching = false;
  bool _updating = false;
  late final TextEditingController _searchController =
      TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Runs a foreground library update. Triggered by the "Refresh" action
  /// or pull-to-refresh — independent of the workmanager schedule (that
  /// fires in the background even when the app is closed).
  Future<void> _refreshLibrary() async {
    if (_updating) return;
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updater = ref.read(libraryUpdaterProvider);
      final result = await updater.updateAll();
      if (!mounted) return;
      final msg = result.newChapters == 0
          ? 'No new chapters found.'
          : '${result.newChapters} new chapter'
              '${result.newChapters == 1 ? '' : 's'} added.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(mangaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search library',
                  border: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.titleLarge,
              )
            : const Text('Library'),
        actions: [
          IconButton(
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh library',
            onPressed: _updating ? null : _refreshLibrary,
          ),
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_searching) {
                  _searching = false;
                  _searchController.clear();
                  _query = '';
                } else {
                  _searching = true;
                }
              });
            },
          ),
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: LibrarySort.titleAsc,
                child: Text('Title (A–Z)'),
              ),
              PopupMenuItem(
                value: LibrarySort.dateAddedDesc,
                child: Text('Recently added'),
              ),
              PopupMenuItem(
                value: LibrarySort.lastUpdateDesc,
                child: Text('Last update'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Manga>>(
        stream: repo.watchFavorites(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const _EmptyLibrary();
          }
          final filtered = _query.isEmpty
              ? items
              : items
                  .where((m) =>
                      m.title.toLowerCase().contains(_query.toLowerCase()))
                  .toList(growable: false);
          final sorted = [...filtered]..sort(_compare(_sort));
          if (sorted.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No matches for "$_query".'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refreshLibrary,
            child: _LibraryGrid(items: sorted),
          );
        },
      ),
    );
  }

  int Function(Manga, Manga) _compare(LibrarySort sort) {
    switch (sort) {
      case LibrarySort.titleAsc:
        return (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case LibrarySort.dateAddedDesc:
        return (a, b) => b.dateAdded.compareTo(a.dateAdded);
      case LibrarySort.lastUpdateDesc:
        return (a, b) => b.lastUpdate.compareTo(a.lastUpdate);
    }
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.items});

  final List<Manga> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.66,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _MangaCard(manga: items[i]),
    );
  }
}

class _MangaCard extends StatelessWidget {
  const _MangaCard({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MangaDetailsScreen(mangaId: manga.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Cover(manga: manga)),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book, size: 48),
      );
    }
    return SourceImage(
      url: url,
      fit: BoxFit.cover,
      placeholder: (_) => Container(color: placeholderColor),
      errorWidget: (_, _) => Container(
        color: placeholderColor,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, size: 36),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_bookmark_outlined, size: 64),
          const SizedBox(height: 12),
          Text(
            'Your library is empty.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Use the Browse tab to add manga to your library.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Failed to load library: $error',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
