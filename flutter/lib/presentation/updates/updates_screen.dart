import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/updates/updates_repository.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';

/// Updates tab -- streams `updatesView` (newly fetched chapters in
/// favourited manga). Mirrors the Kotlin UpdatesTab presentation: cover
/// thumbnail, manga title, chapter name, with read/bookmark/scanlator-mute
/// state baked into the visual treatment.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(updatesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
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
          if (updates.isEmpty) {
            return const _Message(text: 'No new chapters.');
          }
          return ListView.builder(
            itemCount: updates.length,
            itemBuilder: (context, i) => _UpdateTile(update: updates[i]),
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
