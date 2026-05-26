import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';

/// Streams favourited mangas from the DB and renders them as a grid of
/// covers. Tapping a cover will eventually navigate to the manga details
/// screen -- that lives in a follow-up commit.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mangaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
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
          return _LibraryGrid(items: items);
        },
      ),
    );
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
        // TODO(manga-screen): navigate to manga details when that screen
        // exists. Currently a no-op so taps don't feel broken.
        onTap: () {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                // Cover image will be wired up via cached_network_image once
                // the thumbnail-fetching pipeline exists.
                child: const Icon(Icons.menu_book, size: 48),
              ),
            ),
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
