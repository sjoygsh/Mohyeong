// ===========================================================================
// Tide global search.
//
// One query fanned out across every installed source in parallel, one rail per
// source. The rails are the point: results arrive at wildly different speeds,
// so each source owns its own row, its own spinner and its own retry, and a
// slow source never holds up a fast one.
// ===========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/manga/manga_repository.dart';
import '../../data/source/browse_preferences.dart';
import '../../data/source/extension_repository.dart';
import '../../data/source/installed_extension.dart';
import '../../data/source/source_id.dart';
import '../../data/source/source_preferences.dart';
import '../../domain/source/model/source_manga.dart';
import '../common/source_image.dart';
import '../manga/manga_details_screen.dart';
import '../tide/tide.dart';
import 'source_browse_screen.dart';
import '../util/user_message.dart';

/// Mihon's "Global search": takes a query and fans it out across every
/// installed source, showing one horizontal rail per source with the first
/// page of results. Mirrors `GlobalSearchScreen` in the Kotlin app — minus
/// per-source pagination, which the "open source" affordance covers.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');
  String _activeQuery = '';
  // Kotlin SearchScreenModel defaults: pinned sources only, all sections
  // visible regardless of result count.
  bool _pinnedOnly = true;
  bool _onlyShowHasResults = false;

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
      backgroundColor: TideColors.ground,
      body: Stack(
        children: [
          const Positioned.fill(child: TideAurora(opacity: TideAuroraLevel.dense)),
          TideRise(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _searchBar(),
            _scopeChips(),
            Expanded(
              child: _activeQuery.isEmpty
                  ? const _Note(
                      'Type a query and search to look it up across every '
                      'installed source at once.',
                    )
                  : _results(extRepo),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
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
                        controller: _controller,
                        autofocus: true,
                        cursorColor: TideColors.accent,
                        style: TideText.title(size: 14.5),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                          hintText: 'Search every source',
                          hintStyle: TideText.title(
                            size: 14.5,
                            color: TideColors.textAt(0.33),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _submit,
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
    );
  }

  /// Kotlin GlobalSearchToolbar's chip row: Pinned / All source scope, plus
  /// the "Has results" visibility toggle.
  Widget _scopeChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          TideChip(
            label: 'Pinned',
            icon: Icons.push_pin_outlined,
            selected: _pinnedOnly,
            onTap: () => setState(() => _pinnedOnly = true),
          ),
          const SizedBox(width: 8),
          TideChip(
            label: 'All',
            icon: Icons.done_all,
            selected: !_pinnedOnly,
            onTap: () => setState(() => _pinnedOnly = false),
          ),
          const Spacer(),
          TideChip(
            label: 'Has results',
            selected: _onlyShowHasResults,
            onTap: () =>
                setState(() => _onlyShowHasResults = !_onlyShowHasResults),
          ),
        ],
      ),
    );
  }

  Widget _results(ExtensionRepository extRepo) {
    return FutureBuilder<List<InstalledExtension>>(
      future: extRepo.listInstalled(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _Note(userMessage(snap.error!,
              fallback: 'Couldn\'t list your sources.'));
        }
        if (!snap.hasData) {
          return const Center(
            child: TideSpinner(),
          );
        }
        var sources = snap.data!;
        if (sources.isEmpty) {
          return const _Note('No installed sources to search.');
        }
        if (_pinnedOnly) {
          final pinned = ref
                  .watch(sourcePreferencesProvider)
                  .valueOrNull
                  ?.getPinnedSources() ??
              const <String>{};
          sources =
              sources.where((s) => pinned.contains(s.id)).toList(growable: false);
          if (sources.isEmpty) {
            // Verbatim Mihon string no_pinned_sources.
            return const _Note('You have no pinned sources');
          }
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 28),
          itemCount: sources.length,
          itemBuilder: (_, i) => _SourceSection(
            key: ValueKey('${sources[i].id}|$_activeQuery'),
            sourceId: sources[i].id,
            sourceName: sources[i].name,
            query: _activeQuery,
            onlyShowHasResults: _onlyShowHasResults,
          ),
        );
      },
    );
  }
}

/// One rail per source. Loads its own results so a slow source doesn't block
/// faster ones.
class _SourceSection extends ConsumerStatefulWidget {
  const _SourceSection({
    super.key,
    required this.sourceId,
    required this.sourceName,
    required this.query,
    this.onlyShowHasResults = false,
  });

  final String sourceId;
  final String sourceName;
  final String query;

  /// Kotlin `SearchItemResult.isVisible`: while the "Has results" chip is
  /// on, only successfully-loaded, non-empty sections render.
  final bool onlyShowHasResults;

  @override
  ConsumerState<_SourceSection> createState() => _SourceSectionState();
}

class _SourceSectionState extends ConsumerState<_SourceSection> {
  Future<MangasPage>? _future;
  // Tracks whether the search resolved with at least one result, for the
  // "Has results" visibility gate. Null until the future settles.
  bool? _hasResults;

  @override
  void initState() {
    super.initState();
    _kick();
  }

  void _kick() {
    _hasResults = null;
    final repo = ref.read(extensionRepositoryProvider);
    _future = repo
        .getSource(widget.sourceId)
        .then((s) => s.fetchSearch(widget.query, 1))
        .then((page) {
      if (mounted && _hasResults != page.mangas.isNotEmpty) {
        // Schedule after this frame — the FutureBuilder consumes the value
        // in the same build otherwise.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasResults = page.mangas.isNotEmpty);
        });
      }
      return page;
    }, onError: (Object e) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasResults = false);
        });
      }
      throw e; // ignore: only_throw_errors
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onlyShowHasResults && _hasResults != true) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mirrors Kotlin: tapping the source header opens the source with the
        // current query pre-filled.
        TideSectionHeader(
          label: widget.sourceName,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SourceBrowseScreen(
                sourceId: widget.sourceId,
                initialQuery: widget.query,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 196,
          child: FutureBuilder<MangasPage>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) return _error(snap.error);
              if (!snap.hasData) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: TideSpinner(size: 16, strokeWidth: 2),
                  ),
                );
              }
              var items = snap.data!.mangas;
              if (ref.watch(hideInLibraryItemsProvider)) {
                // Only needed for the favorites lookup: keep the
                // sourceNumericId (an MD5 for non-numeric slugs) out of the
                // hot path when the pref is off.
                final sourceIdInt = sourceNumericId(widget.sourceId);
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
                return Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No results found',
                      style: TideText.caption(size: 13, opacity: 0.35),
                    ),
                  ),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(
                  width: 124,
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
    );
  }

  Widget _error(Object? error) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              userMessage(error ?? '', fallback: 'That search failed.'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TideText.caption(size: 12.5, opacity: 0.4),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(_kick),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Retry',
                style: TideText.title(size: 13.5, color: TideColors.accent),
              ),
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
    final url = manga.thumbnailUrl;
    final sourceIdInt = sourceNumericId(sourceId);
    final favoritedUrls = ref
            .watch(favoritedUrlsForSourceProvider(sourceIdInt))
            .valueOrNull ??
        const <String>{};
    final inLibrary = favoritedUrls.contains(manga.url);
    final headers = ref
        .watch(installedSourceImageHeadersProvider)
        .valueOrNull?[sourceIdInt];

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: TideCover.fallbackGradient(manga.url.hashCode),
      ),
    );
    // Mirrors Mihon: covers already in the library are dimmed. Painted via
    // Image.opacity rather than an Opacity widget, which saveLayered every
    // dimmed cell each scrolled frame.
    final cover = (url == null || url.isEmpty)
        ? fallback
        : SourceImage(
            cacheWidth: 360,
            url: url,
            headers: headers,
            fit: BoxFit.cover,
            opacity:
                inLibrary ? const AlwaysStoppedAnimation<double>(0.34) : null,
            placeholder: (_) => fallback,
            errorWidget: (_, _) => fallback,
          );

    return Container(
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            cover,
            const Positioned.fill(child: TideScrim()),
            if (inLibrary)
              const Positioned(top: 7, left: 7, child: TideLibraryMark()),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TideText.title(size: 12.5).copyWith(
                  color: TideColors.brightAt(0.92),
                  height: 1.2,
                ),
              ),
            ),
            // Tap routes via `insertFromSource` into the manga details
            // screen — same flow Mihon uses when picking a result before
            // adding to library.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openManga(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManga(BuildContext context, WidgetRef ref) async {
    final sourceIdInt = sourceNumericId(sourceId);
    final navigator = Navigator.of(context);
    final toast = TideToast.of(context);
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
      toast.show(userMessage(e, fallback: 'Couldn\'t open that entry.'));
    }
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TideText.body(),
          ),
        ),
      );
}
