import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cover/cover_cache.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/manga/model/manga.dart';
import '../common/source_image.dart';
import '../tide/tide.dart';

/// Fullscreen cover viewer reachable by tapping the cover thumbnail on
/// the manga details header. Mirrors a stripped-down version of Mihon's
/// `MangaCoverDialog`: pinch-zoom + tap-to-dismiss with a close button
/// pill in the bottom-left.
///
/// Share/Save/Edit are deliberately not wired — they need `share_plus`
/// (not in pubspec) and a MediaStore registration path on Android for
/// gallery visibility (no analog plumbed yet).
///
/// Removing a custom cover needs none of that plumbing, so it IS wired, in
/// the bottom-right pill and only when there is a custom cover to remove.
/// The reader's "Set as cover" could create one with no way back.
class MangaCoverViewer extends ConsumerWidget {
  const MangaCoverViewer({super.key, required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url =
        ref.watch(coverCacheProvider).coverUrlFor(manga.id, manga.thumbnailUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: url == null || url.isEmpty
                        ? const Icon(
                            Icons.menu_book_outlined,
                            size: 96,
                            color: Colors.white54,
                          )
                        : SourceImage(
                            url: url,
                            fit: BoxFit.contain,
                            placeholder: (_) => const Center(
                              child: TideSpinner(),
                            ),
                            errorWidget: (_, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 64,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _ActionsPill(
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            if (ref.watch(coverCacheProvider).hasCustomCover(manga.id))
              Positioned(
                right: 12,
                bottom: 12,
                child: _ActionsPill(
                  child: IconButton(
                    icon: const Icon(
                      Icons.hide_image_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Remove custom cover',
                    onPressed: () => _removeCustomCover(context, ref),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Reverts to the source artwork — Kotlin's `EditCoverAction.DELETE` /
  /// `MangaCoverScreenModel.deleteCustomCover`.
  Future<void> _removeCustomCover(BuildContext context, WidgetRef ref) async {
    final nav = Navigator.of(context);
    final toast = TideToast.of(context);
    final confirmed = await showTideSheet<bool>(
      context,
      (_) => const TideConfirmSheet(
        title: 'Remove custom cover',
        message: 'The series goes back to the artwork its source provides.',
        confirmLabel: 'Remove',
      ),
    );
    if (confirmed != true) return;
    await ref.read(coverCacheProvider).deleteCustomCover(manga.id);
    // Cover surfaces repaint off cover_last_modified, exactly as they do when
    // the reader sets one; without the bump the grid keeps the old art.
    await ref.read(mangaRepositoryProvider).bumpCoverLastModified(manga.id);
    nav.pop();
    toast.show('Cover removed');
  }
}

class _ActionsPill extends StatelessWidget {
  const _ActionsPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(TideRadius.sheet),
      ),
      child: child,
    );
  }
}
