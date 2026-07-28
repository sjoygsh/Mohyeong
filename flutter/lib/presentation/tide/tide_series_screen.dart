// ===========================================================================
// Tide series.
//
// The cover is the page rather than a thumbnail beside a form: artwork runs
// full-bleed off the top edge and the text rises out of it. Below that the
// order follows what a reader actually wants — what this is, how far in they
// are, then the chapters — with a persistent Continue bar so resuming never
// requires finding the right row.
//
// Chapters are shown newest-first (source order), matching the source's own
// ordering and the app's existing detail screen.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chapter/chapter_repository.dart';
import '../../data/manga/manga_repository.dart';
import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../reader/reader_screen.dart';
import 'tide.dart';

/// Mirrors `SManga.STATUS_*` — 0 Unknown, 1 Ongoing, 2 Completed, 3 Licensed,
/// 4 Publishing finished, 5 Cancelled, 6 On hiatus.
String _statusLabel(int status) => switch (status) {
      1 => 'Ongoing',
      2 => 'Completed',
      3 => 'Licensed',
      4 => 'Finished',
      5 => 'Cancelled',
      6 => 'On hiatus',
      _ => 'Unknown',
    };

class TideSeriesScreen extends ConsumerStatefulWidget {
  const TideSeriesScreen({super.key, required this.mangaId});

  final int mangaId;

  @override
  ConsumerState<TideSeriesScreen> createState() => _TideSeriesScreenState();
}

class _TideSeriesScreenState extends ConsumerState<TideSeriesScreen> {
  late final Stream<Manga?> _manga =
      ref.read(mangaRepositoryProvider).watchById(widget.mangaId);
  late final Stream<List<Chapter>> _chapters =
      ref.read(chapterRepositoryProvider).watchByMangaId(widget.mangaId);

  bool _descriptionExpanded = false;

  /// 0 while the back control is still over the cover, 1 once it is over
  /// the chapter list. Drives [TideTopScrim].
  double _chromeScrim = 0;

  /// Reading order is ascending source order, so the chapter to resume is the
  /// OLDEST unread one — not the newest release.
  Chapter? _next(List<Chapter> chapters) {
    final unread = chapters.where((c) => !c.read).toList()
      ..sort((a, b) => b.sourceOrder.compareTo(a.sourceOrder));
    return unread.firstOrNull;
  }

  /// The chapter the reader is actually part-way through, if any — a started
  /// chapter beats the next untouched one for the Continue bar.
  Chapter? _inProgress(List<Chapter> chapters) {
    final started = chapters
        .where((c) => !c.read && c.lastPageRead > 0)
        .toList()
      ..sort((a, b) => b.sourceOrder.compareTo(a.sourceOrder));
    return started.firstOrNull;
  }

  Future<void> _open(int chapterId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            mangaId: widget.mangaId,
            chapterId: chapterId,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TideColors.ground,
      body: StreamBuilder<Manga?>(
        stream: _manga,
        builder: (context, mangaSnap) {
          final manga = mangaSnap.data;
          if (manga == null) {
            return const Center(
              child: TideSpinner(),
            );
          }
          return StreamBuilder<List<Chapter>>(
            stream: _chapters,
            builder: (context, chapterSnap) {
              final chapters = chapterSnap.data ?? const <Chapter>[];
              return _body(manga, chapters);
            },
          );
        },
      ),
    );
  }

  Widget _body(Manga manga, List<Chapter> chapters) {
    final ordered = [...chapters]
      ..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));
    final readCount = ordered.where((c) => c.read).length;
    final resume = _inProgress(ordered) ?? _next(ordered);

    return TideRise(
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth != 0) return false;
                final next = TideTopScrim.progressFor(
                  n.metrics.pixels,
                  coverHeight: 520,
                );
                if ((next - _chromeScrim).abs() > 0.01) {
                  setState(() => _chromeScrim = next);
                }
                return false;
              },
              child: ListView(
              padding: const EdgeInsets.only(bottom: 108),
              children: [
                // The cover is the page's head and scrolls WITH it. It used to
                // be pinned behind a separately-scrolling list, which meant
                // that the moment you scrolled, the stats and chapter rows sat
                // on top of bright artwork and became unreadable. The scrim
                // ends fully opaque so the handoff to the ground is seamless.
                SizedBox(
                  height: 520,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TideCover(manga: manga, cacheWidth: 900),
                      const TideScrim(opaqueTail: true),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((manga.author ?? '').trim().isNotEmpty)
                              Text(
                                manga.author!.trim().toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TideText.kicker(
                                  color: TideColors.accent,
                                ).copyWith(letterSpacing: 2.2),
                              ),
                            const SizedBox(height: 10),
                            Text(
                              manga.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TideText.display(36),
                            ),
                            if (manga.genre?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final g in manga.genre!.take(4))
                                    TideTag(g),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _Stats(
                  chapters: ordered.length,
                  read: readCount,
                  status: _statusLabel(manga.status),
                ),
                if ((manga.description ?? '').trim().isNotEmpty)
                  _Description(
                    text: manga.description!.trim(),
                    expanded: _descriptionExpanded,
                    onToggle: () => setState(
                      () => _descriptionExpanded = !_descriptionExpanded,
                    ),
                  ),
                const TideSectionHeader(label: 'Chapters', trailing: 'Newest'),
                _ChapterList(
                  chapters: ordered,
                  resumeId: resume?.id,
                  onTap: (c) => _open(c.id),
                ),
              ],
            ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: TideTopScrim(opacity: _chromeScrim),
          ),
          Positioned(
            left: 16,
            top: MediaQuery.paddingOf(context).top + 8,
            child: TideIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 42,
              iconSize: 16,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (resume != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _ContinueBar(
                chapter: resume,
                total: ordered.length,
                read: readCount,
                onTap: () => _open(resume.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three facts, evenly weighted. The design's middle slot is a rating; this
/// app stores none, so the space goes to progress — which is the number a
/// reader is actually looking for here.
class _Stats extends StatelessWidget {
  const _Stats({
    required this.chapters,
    required this.read,
    required this.status,
  });

  final int chapters;
  final int read;
  final String status;

  @override
  Widget build(BuildContext context) {
    final pct = chapters == 0 ? 0 : (read / chapters * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TideGlass(
        radius: 20,
        tintTop: 0.085,
        tintBottom: 0.03,
        highlight: 0.15,
        border: 0.10,
        child: IntrinsicHeight(
          child: Row(
            children: [
              _Stat(value: '$chapters', label: 'Chapters'),
              const _StatDivider(),
              _Stat(value: '$read', label: 'Read'),
              const _StatDivider(),
              _Stat(value: '$pct%', label: status),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.38,
                color: TideColors.textBright,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TideText.kicker(size: 10).copyWith(letterSpacing: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        color: Colors.white.withValues(alpha: 0.09),
      );
}

class _Description extends StatelessWidget {
  const _Description({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: tideEase,
          alignment: Alignment.topCenter,
          child: Text(
            text,
            maxLines: expanded ? null : 4,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: TideText.body(),
          ),
        ),
      ),
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.chapters,
    required this.resumeId,
    required this.onTap,
  });

  final List<Chapter> chapters;
  final int? resumeId;
  final ValueChanged<Chapter> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (i, c) in chapters.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _ChapterRow(
              chapter: c,
              // The row you would land on is lit; everything else is quiet.
              highlighted: c.id == resumeId,
              onTap: () => onTap(c),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.highlighted,
    required this.onTap,
  });

  final Chapter chapter;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final read = chapter.read;
    final started = !read && chapter.lastPageRead > 0;
    final label =
        tideChapterLabel(chapter.name, chapter.chapterNumber);
    final uploaded = chapter.dateUpload > 0
        ? tideRelative(
            DateTime.fromMillisecondsSinceEpoch(chapter.dateUpload),
          )
        : null;

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TideText.title(
                  color: read
                      ? TideColors.textAt(0.55)
                      : (highlighted
                          ? TideColors.textBright
                          : TideColors.text),
                ),
              ),
              if (uploaded != null) ...[
                const SizedBox(height: 2),
                Text(
                  read ? 'Read · $uploaded' : uploaded,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TideText.caption(opacity: read ? 0.35 : 0.42),
                ),
              ],
            ],
          ),
        ),
        if (started) ...[
          const SizedBox(width: 12),
          // A started chapter shows where it was left, not just that it was
          // touched — the ring is the position.
          TideProgressRing(progress: _startedRatio),
        ] else if (chapter.bookmark) ...[
          const SizedBox(width: 12),
          const Icon(Icons.bookmark, size: 16, color: TideColors.accent),
        ],
      ],
    );

    if (highlighted) {
      return TideGlass(
        radius: 16,
        tintTop: 0.16,
        tintBottom: 0.05,
        highlight: 0.18,
        border: 0.28,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: row,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: read ? 0.025 : 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: read ? 0.055 : 0.07),
          ),
        ),
        child: row,
      ),
    );
  }

  /// Page progress within a started chapter. The stored value is a page index
  /// and the total is not recorded, so this shows *that* it is underway with a
  /// conservative arc rather than claiming a precise fraction.
  double get _startedRatio =>
      (chapter.lastPageRead / (chapter.lastPageRead + 8)).clamp(0.05, 0.95);
}

/// Persistent resume affordance. The design's promise is that getting back to
/// where you were is never more than one tap from anywhere in the series.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({
    required this.chapter,
    required this.total,
    required this.read,
    required this.onTap,
  });

  final Chapter chapter;
  final int total;
  final int read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (read / total * 100).round();
    return SizedBox(
      height: 60,
      child: TideGlass(
        radius: 30,
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
                    'CONTINUE',
                    style: TideText.kicker(
                      size: 10,
                      color: TideColors.textAt(0.5),
                    ).copyWith(letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${tideChapterLabel(chapter.name, chapter.chapterNumber)}'
                    ' · $pct%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                Icons.play_arrow_rounded,
                size: 22,
                color: Color(0xFF12141F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
