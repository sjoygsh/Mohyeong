import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library/library_updater.dart';
import '../../data/updates/updates_repository.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

/// Updates tab -- streams `updatesView` (newly fetched chapters in
/// favourited manga). Mirrors the Kotlin UpdatesTab presentation: cover
/// thumbnail, manga title, chapter name, with read/bookmark/scanlator-mute
/// state baked into the visual treatment.
///
/// Pull-to-refresh and the app-bar refresh button both run a foreground
/// library update via `LibraryUpdater.updateAll`; the workmanager
/// schedule continues to run independently in the background.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  bool _updating = false;

  Future<void> _refresh() async {
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
    final repo = ref.watch(updatesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          IconButton(
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Update library',
            onPressed: _updating ? null : _refresh,
          ),
        ],
      ),
      body: StreamBuilder<List<LibraryUpdate>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(text: 'Failed to load updates: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final updates = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: updates.isEmpty
                ? ListView(
                    // ListView so RefreshIndicator still triggers on overscroll.
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [_Message(text: 'No new chapters.')],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: updates.length,
                    itemBuilder: (context, i) =>
                        _UpdateTile(update: updates[i]),
                  ),
          );
        },
      ),
    );
  }
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update});

  final LibraryUpdate update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readColor = theme.disabledColor;
    final defaultColor = theme.colorScheme.onSurface;
    final muted = update.isScanlatorMuted;
    final subtitleBits = <String>[
      update.chapterName,
      if (update.scanlator != null && update.scanlator!.isNotEmpty)
        update.scanlator!,
      if (update.isLinkedAttribution) 'linked source',
    ];
    return ListTile(
      leading: _Thumb(url: update.thumbnailUrl),
      title: Text(
        update.mangaTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: update.read || muted ? readColor : defaultColor,
          decoration: muted ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        subtitleBits.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: update.read ? readColor : defaultColor,
        ),
      ),
      trailing: update.bookmark
          ? const Icon(Icons.bookmark, size: 18)
          : null,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsScreen(mangaId: update.mangaId),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 40,
      height: 56,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book, size: 20),
    );
    if (url == null || url!.isEmpty) return fallback;
    return SizedBox(
      width: 40,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SourceImage(
          url: url!,
          fit: BoxFit.cover,
          placeholder: (_) => fallback,
          errorWidget: (_, _) => fallback,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
