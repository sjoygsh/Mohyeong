import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/browse_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/source_id.dart';
import '../../domain/source/model/source_manga.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';
import 'source_browse_screen.dart';

/// Mihon's "Global search" screen: takes a query and fans it out across
/// every installed source in parallel, showing one horizontal row per
/// source with the first page of results. Mirrors `GlobalSearchScreen`
/// in the Kotlin app — minus per-source pagination, which would need
/// the user to drill in via the "more" affordance.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<GlobalSearchScreen> createState() =>
      _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _activeQuery = widget.initialQuery!.trim();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    if (q == _activeQuery) return;
    setState(() => _activeQuery = q);
  }

  @override
  Widget build(BuildContext context) {
    final extRepo = ref.watch(extensionRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: 'Search every source',
            border: InputBorder.none,
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _submit,
          ),
        ],
      ),
      body: _activeQuery.isEmpty
          ? const _IdleHint()
          : FutureBuilder<List<InstalledExtension>>(
              future: extRepo.listInstalled(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('Failed to enumerate sources: ${snap.error}'),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final sources = snap.data!;
                if (sources.isEmpty) {
                  return const Center(
                    child: Text('No installed sources to search.'),
                  );
                }
                return ListView.builder(
                  itemCount: sources.length,
                  itemBuilder: (_, i) => _SourceSection(
                    key: ValueKey('${sources[i].id}|$_activeQuery'),
                    sourceId: sources[i].id,
                    sourceName: sources[i].name,
                    query: _activeQuery,
                  ),
                );
              },
            ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type a query and press search to look it up across every '
          'installed source in parallel.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ),
    );
  }
}

/// One row per source. Loads its own results lazily so a slow source
/// doesn't block faster ones.
class _SourceSection extends ConsumerStatefulWidget {
  const _SourceSection({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.query,
  });

  final String sourceId;
  final String sourceName;
  final String query;

  @override
  ConsumerState<_SourceSection> createState() => _SourceSectionState();
}

class _SourceSectionState extends ConsumerState<_SourceSection> {
  Future<MangasPage>? _future;

  @override
  void initState() {
    super.initState();
    _kick();
  }

  void _kick() {
    final repo = ref.read(extensionRepositoryProvider);
    _future = repo
        .getSource(widget.sourceId)
        .then((s) => s.fetchSearch(widget.query, 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.sourceName,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SourceBrowseScreen(sourceId: widget.sourceId),
                    ),
                  );
                },
                child: const Text('Open source'),
              ),
            ],
          ),
          SizedBox(
            height: 200,
            child: FutureBuilder<MangasPage>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Error: ${snap.error}',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(_kick),
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                var items = snap.data!.mangas;
                final sourceIdInt = sourceNumericId(widget.sourceId);
                if (ref.watch(hideInLibraryItemsProvider)) {
                  final favoritedUrls = ref
                      .watch(favoritedUrlsForSourceProvider(sourceIdInt))
                      .valueOrNull;
                  if (favoritedUrls != null) {
                    items = items
                        .where((m) => !favoritedUrls.contains(m.url))
                        .toList(growable: false);
                  }
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No matches.',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  );
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                    width: 130,
                    child: _ResultCard(
                      manga: items[i],
                      sourceId: widget.sourceId,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.manga, required this.sourceId});

  final SourceManga manga;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    final url = manga.thumbnailUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null || url.isEmpty)
            Container(color: placeholder)
          else
            SourceImage(
              url: url,
              fit: BoxFit.cover,
              placeholder: (_) => Container(color: placeholder),
              errorWidget: (_, _) => Container(color: placeholder),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          // Tap routes via `insertFromSource` into the manga details
          // screen — same flow Mihon uses when picking a result before
          // adding to library.
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openManga(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openManga(BuildContext context, WidgetRef ref) async {
    final sourceIdInt = sourceNumericId(sourceId);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final inserted = await ref
          .read(mangaRepositoryProvider)
          .insertFromSource(candidate: manga, sourceId: sourceIdInt);
      if (!context.mounted) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(mangaId: inserted.id),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open manga: $e')),
      );
    }
  }
}
