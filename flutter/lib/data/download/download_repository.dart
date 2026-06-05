import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/source/model/source_chapter.dart';
import '../network/app_http_client.dart';
import '../source/extension_repository.dart';

/// Per-architecture-decisions: downloads live inside the app's data
/// directory (deviates from Mihon, which uses SAF/external storage).
/// Layout under `<appSupport>/downloads/`:
///   `<source_id>/<manga_id>/<chapter_id>/`
///     `001.<ext>` ... `NNN.<ext>` - page image files
///     `.done`                     - marker file written after the last page
///                                   downloads successfully. Its presence
///                                   means the chapter is fully downloaded.
///
/// A queue + manager runs downloads serially. Pending state lives in
/// memory; on restart, in-progress downloads are simply forgotten and can
/// be re-queued by the user (already-finished chapters are detected via
/// the `.done` marker).
class DownloadRepository {
  DownloadRepository(this._extensions, this._http);

  final ExtensionRepository _extensions;
  final AppHttpClient _http;
  Dio get _dio => _http.dio;

  Directory? _rootCache;
  final List<_DownloadJob> _queue = [];
  final Map<int, _DownloadJob> _byChapter = {}; // chapterId -> job
  bool _running = false;
  bool _paused = false;

  final _events = StreamController<DownloadEvent>.broadcast();
  Stream<DownloadEvent> get events => _events.stream;

  /// Whether new queued jobs are blocked from starting. The currently
  /// running job (if any) keeps going — we don't have `CancelToken`
  /// plumbed yet — so pause is effectively "no new jobs after this
  /// one". UI reads this to flip the pause/resume affordance.
  bool get isPaused => _paused;

  /// Stop pulling jobs from the queue. The in-flight job finishes
  /// normally. Subsequent calls to [enqueue] still queue rows but the
  /// drain loop won't start them until [resumeQueue] is called.
  void pauseQueue() {
    if (_paused) return;
    _paused = true;
    _events.add(const DownloadEvent.queuePaused());
  }

  /// Resume pulling jobs from the queue. Kicks the drain loop if there's
  /// anything pending so the UI sees activity immediately.
  void resumeQueue() {
    if (!_paused) return;
    _paused = false;
    _events.add(const DownloadEvent.queueResumed());
    unawaited(_drain());
  }

  Future<Directory> _root() async {
    final cached = _rootCache;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootCache = dir;
    return dir;
  }

  Directory _chapterDirSync(
    Directory root,
    int sourceId,
    int mangaId,
    int chapterId,
  ) {
    return Directory(p.join(
      root.path,
      sourceId.toString(),
      mangaId.toString(),
      chapterId.toString(),
    ));
  }

  Future<Directory> _chapterDir(int sourceId, int mangaId, int chapterId) async {
    return _chapterDirSync(await _root(), sourceId, mangaId, chapterId);
  }

  Future<bool> isDownloaded(int sourceId, int mangaId, int chapterId) async {
    final dir = await _chapterDir(sourceId, mangaId, chapterId);
    final marker = File(p.join(dir.path, '.done'));
    return marker.exists();
  }

  /// Number of fully-downloaded chapters for [mangaId]. Walks the
  /// `<root>/<sourceId>/<mangaId>/` directory and counts subdirectories
  /// that carry a `.done` marker. Returns 0 if the manga has no
  /// downloads directory at all.
  Future<int> countDownloadedForManga(int sourceId, int mangaId) async {
    final root = await _root();
    final mangaDir = Directory(
      p.join(root.path, sourceId.toString(), mangaId.toString()),
    );
    if (!await mangaDir.exists()) return 0;
    var count = 0;
    await for (final entity in mangaDir.list()) {
      if (entity is Directory) {
        final marker = File(p.join(entity.path, '.done'));
        if (await marker.exists()) count++;
      }
    }
    return count;
  }

  /// Set of `(sourceId, mangaId)` pairs that have at least one fully
  /// downloaded chapter. Walks the downloads root once so the library
  /// filter sheet can apply a Downloaded axis without an N-call probe.
  /// Returns the pair as a `int` key encoded as `source << 32 | manga`
  /// (both are 32-bit-fitting in our schema, manga.id auto-increments).
  Future<Set<int>> listMangaWithAnyDownload() async {
    final root = await _root();
    if (!await root.exists()) return const <int>{};
    final out = <int>{};
    await for (final sourceDir in root.list()) {
      if (sourceDir is! Directory) continue;
      final sourceId = int.tryParse(p.basename(sourceDir.path));
      if (sourceId == null) continue;
      await for (final mangaDir in sourceDir.list()) {
        if (mangaDir is! Directory) continue;
        final mangaId = int.tryParse(p.basename(mangaDir.path));
        if (mangaId == null) continue;
        // First .done marker wins; bail out for this manga as soon as
        // any chapter qualifies.
        var hasOne = false;
        await for (final chapterDir in mangaDir.list()) {
          if (chapterDir is! Directory) continue;
          final marker = File(p.join(chapterDir.path, '.done'));
          if (await marker.exists()) {
            hasOne = true;
            break;
          }
        }
        if (hasOne) out.add((sourceId << 32) | mangaId);
      }
    }
    return out;
  }

  /// Convenience encoding shared with [listMangaWithAnyDownload]. Pure
  /// helper — exposed so callers can probe the returned set without
  /// duplicating the bit shuffle.
  static int encodeMangaKey(int sourceId, int mangaId) =>
      (sourceId << 32) | mangaId;

  /// Set of chapter ids that are fully downloaded for [mangaId]. Cheaper
  /// than calling [isDownloaded] per chapter when filtering a chapter
  /// list, since it walks the manga directory once.
  Future<Set<int>> listDownloadedChapterIds(
    int sourceId,
    int mangaId,
  ) async {
    final root = await _root();
    final mangaDir = Directory(
      p.join(root.path, sourceId.toString(), mangaId.toString()),
    );
    if (!await mangaDir.exists()) return const <int>{};
    final ids = <int>{};
    await for (final entity in mangaDir.list()) {
      if (entity is! Directory) continue;
      final marker = File(p.join(entity.path, '.done'));
      if (!await marker.exists()) continue;
      final parsed = int.tryParse(p.basename(entity.path));
      if (parsed != null) ids.add(parsed);
    }
    return ids;
  }

  /// Returns the list of locally-cached page paths for a downloaded chapter,
  /// or null if the chapter isn't fully downloaded.
  Future<List<String>?> localPagePaths(
    int sourceId,
    int mangaId,
    int chapterId,
  ) async {
    final dir = await _chapterDir(sourceId, mangaId, chapterId);
    final marker = File(p.join(dir.path, '.done'));
    if (!await marker.exists()) return null;
    final files = await dir
        .list()
        .where((e) =>
            e is File &&
            p.basename(e.path) != '.done' &&
            // A CBZ-archived chapter has no loose page files for the reader
            // to consume directly; reading from the archive needs a
            // separate unzip path (see TODO in localPagePaths). Skip the
            // archive so we don't hand a zip to the image pipeline.
            p.extension(e.path).toLowerCase() != '.cbz')
        .map((e) => e.path)
        .toList();
    files.sort();
    // TODO(cbz-read): when the chapter was saved as CBZ, `files` is empty
    // here. Reading a CBZ-archived chapter requires unzipping pages from
    // `<chapterId>.cbz` (the reader path is owned by another module).
    return files;
  }

  Future<void> deleteDownload(
    int sourceId,
    int mangaId,
    int chapterId,
  ) async {
    final dir = await _chapterDir(sourceId, mangaId, chapterId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _events.add(
      DownloadEvent(chapterId: chapterId, state: DownloadState.deleted),
    );
  }

  /// Wipes the entire `<root>/<sourceId>/<mangaId>/` directory tree —
  /// every downloaded chapter for the manga. Used by the library bulk
  /// remove flow when the user opts to free up storage. Returns the
  /// number of chapter dirs deleted so the caller can report progress.
  Future<int> deleteAllForManga(int sourceId, int mangaId) async {
    final root = await _root();
    final mangaDir = Directory(
      p.join(root.path, sourceId.toString(), mangaId.toString()),
    );
    if (!await mangaDir.exists()) return 0;
    var count = 0;
    await for (final entity in mangaDir.list()) {
      if (entity is Directory) {
        final parsed = int.tryParse(p.basename(entity.path));
        if (parsed != null) {
          _events.add(
            DownloadEvent(chapterId: parsed, state: DownloadState.deleted),
          );
        }
        count++;
      }
    }
    await mangaDir.delete(recursive: true);
    return count;
  }

  /// Enqueues a chapter for download. Idempotent: re-queueing a chapter
  /// already in the queue or already downloaded is a no-op.
  Future<void> enqueue(Manga manga, Chapter chapter) async {
    final existing = _byChapter[chapter.id];
    if (existing != null) return;
    if (await isDownloaded(manga.source, manga.id, chapter.id)) {
      _events.add(
        DownloadEvent(chapterId: chapter.id, state: DownloadState.completed),
      );
      return;
    }
    final job = _DownloadJob(manga: manga, chapter: chapter);
    _queue.add(job);
    _byChapter[chapter.id] = job;
    _events.add(
      DownloadEvent(chapterId: chapter.id, state: DownloadState.queued),
    );
    unawaited(_drain());
  }

  /// How many chapters to download concurrently. Read fresh from
  /// SharedPreferences (`download_slots`, 1..5) at the start of each drain
  /// so a settings change takes effect on the next batch. Defaults to
  /// serial (1) when unset or out of range.
  Future<int> _maxConcurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('download_slots') ?? 1;
    return v.clamp(1, 5);
  }

  /// Whether completed chapters should be archived into a single CBZ.
  /// Read fresh from SharedPreferences (`save_chapter_as_cbz`, mirroring
  /// Mihon's key) at finalize time so a settings change applies to the
  /// next chapter without restart. Defaults to off.
  Future<bool> _saveAsCbz() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('save_chapter_as_cbz') ?? false;
  }

  /// Zips the chapter's page images into `<chapterId>.cbz` inside the same
  /// chapter directory, then writes the `.done` marker and removes the
  /// loose page files. The `.cbz` and `.done` are the only survivors, so
  /// existing `.done`-based completion checks keep working unchanged.
  Future<void> _archiveChapterAsCbz(Directory dir, List<File> pages) async {
    final cbzPath = p.join(dir.path, '${p.basename(dir.path)}.cbz');
    final encoder = ZipFileEncoder();
    encoder.create(cbzPath);
    try {
      for (final page in pages) {
        if (await page.exists()) {
          await encoder.addFile(page, p.basename(page.path));
        }
      }
    } finally {
      await encoder.close();
    }
    // Drop the loose page images now that they're inside the archive.
    for (final page in pages) {
      if (await page.exists()) await page.delete();
    }
    await File(p.join(dir.path, '.done')).create();
  }

  /// Completes once the queue has fully drained (no running batch and
  /// nothing pending). Used by the background library-update isolate to
  /// keep its short-lived process alive until auto-downloads finish, since
  /// closing the DB/HTTP client mid-download would abort them. Polls rather
  /// than using a completer because the drain loop is fire-and-forget.
  Future<void> awaitIdle() async {
    while (_running || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _drain() async {
    if (_running || _paused) return;
    _running = true;
    try {
      final concurrency = await _maxConcurrent();
      final active = <Future<void>>{};
      while (!_paused && (_queue.isNotEmpty || active.isNotEmpty)) {
        // Top up the in-flight set until we hit the concurrency cap or
        // run out of queued jobs.
        while (!_paused && _queue.isNotEmpty && active.length < concurrency) {
          final job = _queue.removeAt(0);
          late final Future<void> f;
          f = _runJob(job).whenComplete(() {
            _byChapter.remove(job.chapter.id);
            active.remove(f);
          });
          active.add(f);
        }
        if (active.isEmpty) break;
        // Wait for at least one job to finish, then re-fill.
        await Future.any(active);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runJob(_DownloadJob job) async {
    final manga = job.manga;
    final chapter = job.chapter;
    _events.add(
      DownloadEvent(chapterId: chapter.id, state: DownloadState.downloading),
    );
    try {
      final source = await _extensions.getSource(manga.source.toString());
      final pages = await source.fetchPageList(
        SourceChapter(url: chapter.url, name: chapter.name),
      );
      final dir = await _chapterDir(manga.source, manga.id, chapter.id);
      if (!await dir.exists()) await dir.create(recursive: true);
      job.totalPages = pages.length;
      job.downloadedPages = 0;
      final pageFiles = <File>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final imageUrl = page.imageUrl ?? page.url;
        final ext = _extForUrl(imageUrl);
        final target = File(p.join(
          dir.path,
          '${(i + 1).toString().padLeft(4, '0')}.$ext',
        ));
        if (!await target.exists()) {
          await _dio.download(
            imageUrl,
            target.path,
            options: Options(headers: page.headers),
          );
        }
        pageFiles.add(target);
        job.downloadedPages = i + 1;
        _events.add(
          DownloadEvent(
            chapterId: chapter.id,
            state: DownloadState.downloading,
            progress: (i + 1) / pages.length,
            downloadedPages: i + 1,
            totalPages: pages.length,
          ),
        );
      }
      // Optionally archive the chapter into a single CBZ alongside the
      // page folder, mirroring Mihon's `saveChaptersAsCBZ`. The folder is
      // removed once the archive is written so a chapter lives as exactly
      // one of {folder, cbz}, matching Mihon's on-disk shape.
      if (await _saveAsCbz()) {
        await _archiveChapterAsCbz(dir, pageFiles);
      } else {
        await File(p.join(dir.path, '.done')).create();
      }
      _events.add(
        DownloadEvent(chapterId: chapter.id, state: DownloadState.completed),
      );
    } catch (e) {
      _events.add(
        DownloadEvent(
          chapterId: chapter.id,
          state: DownloadState.failed,
          error: e.toString(),
        ),
      );
    }
  }

  String _extForUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    // Trim query strings the URI parser missed (e.g. "jpg?token=...").
    final q = ext.indexOf(RegExp(r'[?#&]'));
    final clean = q < 0 ? ext : ext.substring(0, q);
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif'};
    return allowed.contains(clean) ? clean : 'jpg';
  }

  /// Snapshot of everything the queue currently knows about, in
  /// queued-then-running order. Used by the Downloads screen to show
  /// "what's pending". `current` flags the job that's actively
  /// downloading (always at most one — the queue is serial).
  List<ActiveDownload> snapshot() {
    final running = _byChapter.values
        .where((j) => !_queue.contains(j))
        .toList(growable: false);
    return [
      for (final j in running)
        ActiveDownload(
          manga: j.manga,
          chapter: j.chapter,
          current: true,
          downloadedPages: j.downloadedPages,
          totalPages: j.totalPages,
        ),
      for (final j in _queue)
        ActiveDownload(
          manga: j.manga,
          chapter: j.chapter,
          current: false,
          downloadedPages: j.downloadedPages,
          totalPages: j.totalPages,
        ),
    ];
  }

  /// Removes a queued chapter. The currently-running job can't be
  /// cancelled (Dio download is in-flight and there's no cancel token
  /// threaded through yet — would need wider plumbing).
  bool cancelQueued(int chapterId) {
    final job = _byChapter[chapterId];
    if (job == null) return false;
    final idx = _queue.indexOf(job);
    if (idx < 0) return false; // currently running, not queued.
    _queue.removeAt(idx);
    _byChapter.remove(chapterId);
    _events.add(
      DownloadEvent(chapterId: chapterId, state: DownloadState.deleted),
    );
    return true;
  }

  /// Moves a queued chapter to [newQueueIndex] in the queue (0 = head of
  /// the queue, i.e. next to run after the current job finishes). The
  /// currently-running job is unaffected — it can't be reordered, since
  /// it's no longer in `_queue`. Re-emits a `queued` event for the
  /// chapter so any listening UI (the queue screen) repaints.
  ///
  /// Returns `true` when the move actually happened; `false` if the
  /// chapter isn't queued or [newQueueIndex] would be a no-op.
  bool reorderQueue(int chapterId, int newQueueIndex) {
    final job = _byChapter[chapterId];
    if (job == null) return false;
    final oldIndex = _queue.indexOf(job);
    if (oldIndex < 0) return false; // currently running — not in _queue.
    final clamped = newQueueIndex.clamp(0, _queue.length - 1);
    if (clamped == oldIndex) return false;
    _queue.removeAt(oldIndex);
    _queue.insert(clamped, job);
    _events.add(
      DownloadEvent(chapterId: chapterId, state: DownloadState.queued),
    );
    return true;
  }

  /// Drops every queued chapter, leaving the in-flight job to finish.
  /// Returns the number of jobs removed.
  int clearQueue() {
    final removed = List<_DownloadJob>.from(_queue);
    _queue.clear();
    for (final j in removed) {
      _byChapter.remove(j.chapter.id);
      _events.add(
        DownloadEvent(chapterId: j.chapter.id, state: DownloadState.deleted),
      );
    }
    return removed.length;
  }

  Future<void> close() async {
    await _events.close();
  }
}

/// Public view of a queued or in-flight download. Mirrors the
/// "Downloads" tab list rows in Mihon.
class ActiveDownload {
  const ActiveDownload({
    required this.manga,
    required this.chapter,
    required this.current,
    this.downloadedPages = 0,
    this.totalPages = 0,
  });

  final Manga manga;
  final Chapter chapter;

  /// True if this is the job currently being downloaded; false for
  /// items still waiting in the queue.
  final bool current;

  /// Pages fetched so far for this chapter (0 until downloading starts).
  final int downloadedPages;

  /// Total pages in this chapter (0 until the page list resolves).
  final int totalPages;
}

class _DownloadJob {
  _DownloadJob({required this.manga, required this.chapter});
  final Manga manga;
  final Chapter chapter;

  /// Pages fetched so far / total pages for the chapter. Both 0 until the
  /// page list is resolved. Surfaced through [ActiveDownload] so the queue
  /// screen can show "x/y".
  int downloadedPages = 0;
  int totalPages = 0;
}

enum DownloadState {
  queued,
  downloading,
  completed,
  failed,
  deleted,
  // Whole-queue lifecycle events — `chapterId` is unused for these (set
  // to 0). Listeners that care about per-row state can ignore them; the
  // queue screen uses them to refresh its pause/resume button.
  queuePaused,
  queueResumed,
}

class DownloadEvent {
  const DownloadEvent({
    required this.chapterId,
    required this.state,
    this.progress,
    this.error,
    this.downloadedPages,
    this.totalPages,
  });

  const DownloadEvent.queuePaused()
      : chapterId = 0,
        state = DownloadState.queuePaused,
        progress = null,
        error = null,
        downloadedPages = null,
        totalPages = null;

  const DownloadEvent.queueResumed()
      : chapterId = 0,
        state = DownloadState.queueResumed,
        progress = null,
        error = null,
        downloadedPages = null,
        totalPages = null;

  final int chapterId;
  final DownloadState state;
  final double? progress;
  final String? error;

  /// Pages fetched so far for this chapter, when known.
  final int? downloadedPages;

  /// Total pages in this chapter, when known.
  final int? totalPages;
}

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final ext = ref.watch(extensionRepositoryProvider);
  final http = ref.watch(appHttpClientProvider);
  return DownloadRepository(ext, http);
});
