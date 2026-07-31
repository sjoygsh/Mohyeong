import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/chapter/model/chapter.dart';
import '../../domain/manga/model/manga.dart';
import '../../domain/source/model/source_chapter.dart';
import '../network/app_http_client.dart';
import '../notification/notification_service.dart';
import '../source/local_archive.dart';
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
  DownloadRepository(this._extensions, this._http) {
    // A network change might newly permit (or forbid) downloads. Re-kick
    // the drain loop; it re-checks the current network itself and either
    // resumes pulling jobs or re-enters the waiting-for-network state.
    _connSub = _connectivity.onConnectivityChanged.listen((_) {
      if (_paused || _queue.isEmpty) return;
      unawaited(_drain());
    });
  }

  final ExtensionRepository _extensions;
  final AppHttpClient _http;
  Dio get _dio => _http.dio;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  Directory? _rootCache;
  final List<_DownloadJob> _queue = [];
  final Map<int, _DownloadJob> _byChapter = {}; // chapterId -> job
  bool _running = false;
  bool _paused = false;

  /// True while the queue is stalled purely because the current network
  /// doesn't satisfy the "only over Wi-Fi" policy (or the device is
  /// offline). Distinct from [isPaused], which is user-initiated.
  bool _networkBlocked = false;
  bool get isWaitingForNetwork => _networkBlocked;

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

  // ---- Downloaded-chapters index ------------------------------------
  //
  // In-memory view of every fully-downloaded chapter, keyed by
  // [encodeMangaKey] with the set of downloaded chapter ids as the value.
  // Built from ONE walk of the downloads tree on first use, then maintained
  // incrementally by the mutators in this class (the only writers of `.done`
  // markers). Before this, every consumer re-walked directories with a
  // `.done` stat per chapter: the library badges provider after each
  // completion burst, the details screen on every open, the library filter
  // per resolve, bulk enqueue per chapter.
  //
  // Blind spot (documented, matches where the old event-driven refreshes
  // were already blind): the scheduled background update runs in its own
  // engine isolate with its own repository, so its auto-downloads don't flow
  // through these mutators. [invalidateDownloadedIndex] is called on app
  // resume to pick those up; reading pages stays correct regardless because
  // [localPagePaths] checks the real filesystem.
  Map<String, Set<int>>? _downloadedIdx;
  Future<Map<String, Set<int>>>? _downloadedIdxBuild;
  int _downloadedIdxGen = 0;

  Future<Map<String, Set<int>>> _downloadedIndex() {
    final idx = _downloadedIdx;
    if (idx != null) return Future.value(idx);
    final building = _downloadedIdxBuild;
    if (building != null) return building;
    final gen = _downloadedIdxGen;
    late final Future<Map<String, Set<int>>> future;
    future = () async {
      final Map<String, Set<int>> built;
      try {
        built = await _walkDownloadedIndex();
      } catch (_) {
        // A failed walk must not stay memoised — every later lookup would
        // replay the same error until the next invalidation. Clear so the
        // next reader retries. (The walk itself tolerates directories
        // vanishing under it; this guards whatever else can throw.)
        if (identical(_downloadedIdxBuild, future)) _downloadedIdxBuild = null;
        rethrow;
      }
      if (gen != _downloadedIdxGen) {
        // Invalidated while walking — the snapshot may miss out-of-band
        // changes; rebuild on the current generation.
        return _downloadedIndex();
      }
      _downloadedIdx = built;
      _downloadedIdxBuild = null;
      return built;
    }();
    return _downloadedIdxBuild = future;
  }

  /// Lists [dir], treating a directory that vanished (or turned unreadable)
  /// between discovery and listing as empty. The downloads tree is mutated
  /// concurrently with the walk — a chapter/manga delete recursively removes
  /// directories the walk may already hold — and the mutators re-apply their
  /// change on top of the built index anyway.
  Stream<FileSystemEntity> _listSafe(Directory dir) async* {
    try {
      yield* dir.list();
    } on FileSystemException {
      // Skip what disappeared mid-walk.
    }
  }

  Future<Map<String, Set<int>>> _walkDownloadedIndex() async {
    final root = await _root();
    final out = <String, Set<int>>{};
    if (!await root.exists()) return out;
    await for (final sourceDir in _listSafe(root)) {
      if (sourceDir is! Directory) continue;
      final sourceId = int.tryParse(p.basename(sourceDir.path));
      if (sourceId == null) continue;
      await for (final mangaDir in _listSafe(sourceDir)) {
        if (mangaDir is! Directory) continue;
        final mangaId = int.tryParse(p.basename(mangaDir.path));
        if (mangaId == null) continue;
        final ids = <int>{};
        await for (final chapterDir in _listSafe(mangaDir)) {
          if (chapterDir is! Directory) continue;
          final chapterId = int.tryParse(p.basename(chapterDir.path));
          if (chapterId == null) continue;
          final marker = File(p.join(chapterDir.path, '.done'));
          if (await marker.exists()) ids.add(chapterId);
        }
        if (ids.isNotEmpty) out[encodeMangaKey(sourceId, mangaId)] = ids;
      }
    }
    return out;
  }

  /// Applies [mutate] to the index: immediately when it's built, after the
  /// in-flight build when one is running (the walk may or may not have seen
  /// the filesystem change — applying on top is correct either way for the
  /// idempotent add/remove mutations this class does), and not at all when
  /// no one has requested the index yet (the eventual first walk reads the
  /// post-mutation filesystem).
  void _updateDownloadedIndex(
    void Function(Map<String, Set<int>> index) mutate,
  ) {
    final idx = _downloadedIdx;
    if (idx != null) {
      mutate(idx);
      return;
    }
    final building = _downloadedIdxBuild;
    if (building != null) {
      building.then((_) {
        final built = _downloadedIdx;
        if (built != null) mutate(built);
      }, onError: (_) {
        // Build failed — nothing to patch; the walk that eventually
        // succeeds reads the post-mutation filesystem. Without this
        // handler the derived future's error is unhandled.
      });
    }
  }

  void _indexAdd(int sourceId, int mangaId, int chapterId) {
    _updateDownloadedIndex(
      (idx) =>
          (idx[encodeMangaKey(sourceId, mangaId)] ??= <int>{}).add(chapterId),
    );
  }

  void _indexRemove(int sourceId, int mangaId, int chapterId) {
    _updateDownloadedIndex((idx) {
      final key = encodeMangaKey(sourceId, mangaId);
      final ids = idx[key];
      if (ids != null && ids.remove(chapterId) && ids.isEmpty) {
        idx.remove(key);
      }
    });
  }

  /// Drops the in-memory index so the next reader rebuilds it from the
  /// filesystem. Call when downloads may have changed outside this isolate
  /// (the scheduled background update's engine isolate owns a separate
  /// repository instance) — the home shell calls this on app resume.
  void invalidateDownloadedIndex() {
    _downloadedIdxGen++;
    _downloadedIdx = null;
    _downloadedIdxBuild = null;
  }

  Future<bool> isDownloaded(int sourceId, int mangaId, int chapterId) async {
    final idx = await _downloadedIndex();
    return idx[encodeMangaKey(sourceId, mangaId)]?.contains(chapterId) ??
        false;
  }

  /// Total number of fully-downloaded chapters across every source/manga.
  /// Mirrors Mihon's `DownloadManager.getDownloadCount()` (used by the
  /// Statistics screen). Returns 0 when nothing has been downloaded yet.
  Future<int> totalDownloadedCount() async {
    final idx = await _downloadedIndex();
    var count = 0;
    for (final ids in idx.values) {
      count += ids.length;
    }
    return count;
  }

  /// Set of `(sourceId, mangaId)` pairs that have at least one fully
  /// downloaded chapter, so the library filter sheet can apply a Downloaded
  /// axis without an N-call probe. Returns each pair as a `"source/manga"`
  /// string key ([encodeMangaKey]).
  Future<Set<String>> listMangaWithAnyDownload() async {
    final idx = await _downloadedIndex();
    return idx.keys.toSet();
  }

  /// Downloaded-chapter counts for EVERY manga (key = [encodeMangaKey]).
  /// Feeds the library's downloaded badges.
  Future<Map<String, int>> downloadedCountsByManga() async {
    final idx = await _downloadedIndex();
    return {for (final e in idx.entries) e.key: e.value.length};
  }

  /// Composite `(sourceId, mangaId)` key shared with
  /// [listMangaWithAnyDownload] / [downloadedCountsByManga]. A string
  /// rather than the old `source << 32 | manga` packing, which overflowed
  /// 64 bits for the large hashed source ids JS extensions use and could
  /// collide two distinct pairs onto one key.
  static String encodeMangaKey(int sourceId, int mangaId) =>
      '$sourceId/$mangaId';

  /// Set of chapter ids that are fully downloaded for [mangaId]. Cheaper
  /// than calling [isDownloaded] per chapter when filtering a chapter
  /// list. Returns a copy — callers mutate it as their own live state.
  Future<Set<int>> listDownloadedChapterIds(
    int sourceId,
    int mangaId,
  ) async {
    final idx = await _downloadedIndex();
    final ids = idx[encodeMangaKey(sourceId, mangaId)];
    return ids == null ? const <int>{} : {...ids};
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
    final entries = await dir.list().toList();
    // A CBZ-archived chapter has no loose page files; its pages live inside
    // `<chapterId>.cbz`. Hand the reader `archive://` page URLs that
    // [SourceImage] decodes via the shared archive pipeline, mirroring how
    // the Local source serves its `.cbz` chapters.
    final cbz = entries.firstWhere(
      (e) => e is File && p.extension(e.path).toLowerCase() == '.cbz',
      orElse: () => dir, // sentinel: no archive present
    );
    if (cbz is File) {
      final names = await listArchiveImageEntries(cbz.path);
      names.sort();
      return [for (final name in names) encodeArchivePageUrl(cbz.path, name)];
    }
    final files = entries
        .whereType<File>()
        .where((e) => p.basename(e.path) != '.done')
        // Never serve an interrupted page write as a page (see _downloadPage).
        .where((e) => p.extension(e.path) != '.part')
        .map((e) => e.path)
        .toList();
    files.sort();
    return files;
  }

  Future<void> deleteDownload(
    int sourceId,
    int mangaId,
    int chapterId,
  ) async {
    // Delete is offered for a chapter in any state, including one being
    // written right now. Left running, that job keeps writing pages into a
    // directory that no longer exists, and the FileSystemException it dies
    // of is not a cancel — so it registers as a retryable "errored" queue
    // entry for a chapter the user just deleted. Stop it first; its cancel
    // branch is idempotent about the directory already being gone.
    cancel(chapterId);
    final dir = await _chapterDir(sourceId, mangaId, chapterId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _indexRemove(sourceId, mangaId, chapterId);
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
    // Same reasoning as deleteDownload, for every job belonging to this
    // manga — queued ones included, since they would otherwise start writing
    // into the tree moments after it was removed.
    final doomed = _byChapter.values
        .where((j) => j.manga.id == mangaId && j.manga.source == sourceId)
        .map((j) => j.chapter.id)
        .toList();
    for (final id in doomed) {
      cancel(id);
    }
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
    _updateDownloadedIndex(
      (idx) => idx.remove(encodeMangaKey(sourceId, mangaId)),
    );
    return count;
  }

  /// Enqueues a chapter for download. Idempotent: re-queueing a chapter
  /// already in the queue or already downloaded is a no-op.
  Future<void> enqueue(Manga manga, Chapter chapter) async {
    final existing = _byChapter[chapter.id];
    if (existing != null) return;
    // Reserve the slot BEFORE the isDownloaded await: two concurrent
    // enqueues of one chapter (an update-sweep worker racing the details
    // screen's refresh) both passed the lookup and double-queued it, and
    // the second overwrote _byChapter so cancel only saw one of them.
    final job = _DownloadJob(manga: manga, chapter: chapter);
    _byChapter[chapter.id] = job;
    if (await isDownloaded(manga.source, manga.id, chapter.id)) {
      if (_byChapter[chapter.id] == job) _byChapter.remove(chapter.id);
      _events.add(
        DownloadEvent(chapterId: chapter.id, state: DownloadState.completed),
      );
      return;
    }
    _queue.add(job);
    _events.add(
      DownloadEvent(chapterId: chapter.id, state: DownloadState.queued),
    );
    unawaited(_drain());
  }

  /// How many chapters to download concurrently. Read fresh from
  /// SharedPreferences (`download_parallel_source_limit`, 1..10) at the start
  /// of each drain so a settings change takes effect on the next batch.
  /// Defaults to 5 (Mihon's default) when unset, clamped to range.
  Future<int> _maxConcurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('download_parallel_source_limit') ?? 5;
    return v.clamp(1, 10);
  }

  /// How many pages of a single chapter to download concurrently. Read fresh
  /// from SharedPreferences (`download_parallel_page_limit`, 1..15) per
  /// chapter. Defaults to 5 (Mihon's default) when unset, clamped to range.
  Future<int> _maxPageConcurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('download_parallel_page_limit') ?? 5;
    return v.clamp(1, 15);
  }

  /// Whether downloads are restricted to un-metered (Wi-Fi/Ethernet)
  /// connections. Read fresh from SharedPreferences at each network check
  /// (verbatim Mihon key `pref_download_only_over_wifi_key`, default on) so
  /// toggling the setting takes effect without restart.
  Future<bool> _downloadOnlyOverWifi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pref_download_only_over_wifi_key') ?? true;
  }

  /// Mirrors Mihon's `checkNetworkState`: downloads are allowed only when
  /// the device is online, and — when "only over Wi-Fi" is enabled — only
  /// over an un-metered transport (Wi-Fi or Ethernet). Mobile and other
  /// transports are treated as metered.
  Future<bool> _networkAllowsDownload() async {
    final result = await _connectivity.checkConnectivity();
    final online = result.any((r) => r != ConnectivityResult.none);
    if (!online) return false;
    if (!await _downloadOnlyOverWifi()) return true;
    return result.any((r) =>
        r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
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

  /// Every notification this repository posts goes through one chain, and the
  /// drain's closing cancel is the last link in it. Posting them loose would
  /// let a page's `show` land *after* the queue-finished `cancel` and pin a
  /// dead progress bar to the shade — the foreground library update hit
  /// exactly that bug and serialises for the same reason.
  Future<void> _notifChain = Future<void>.value();
  DateTime _lastProgressNotif = DateTime.fromMillisecondsSinceEpoch(0);

  void _queueNotification(Future<void> Function() op) {
    // A notification failing (channel gone, permission revoked mid-run) must
    // never take a download down with it.
    _notifChain = _notifChain.then((_) => op()).catchError((_) {});
  }

  /// Mirrors Kotlin's `DownloadNotifier`: one ongoing notification tracking
  /// whatever is downloading now. Throttled because several jobs each
  /// finishing pages would otherwise post dozens of updates a second, and the
  /// bar only has to look alive. The last page of a chapter always posts so
  /// the count never rests on a stale number.
  void _notifyProgress(_DownloadJob job, int done, int total) {
    final now = DateTime.now();
    if (done < total &&
        now.difference(_lastProgressNotif) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastProgressNotif = now;
    // Kotlin strips a leading series title off the chapter name before
    // joining the two, so a source that names chapters "<Series> Chapter 12"
    // doesn't produce "<Series> - <Series> Chapter 12".
    final title = job.manga.title;
    final chapterName = job.chapter.name.replaceFirst(
      RegExp('^${RegExp.escape(title)}\\s*[-–]?\\s*', caseSensitive: false),
      '',
    );
    _queueNotification(
      () => NotificationService.instance.showDownloadProgress(
        title: '$title · $chapterName',
        downloaded: done,
        total: total,
      ),
    );
  }

  Future<void> _drain() async {
    if (_running || _paused) return;
    _running = true;
    try {
      final concurrency = await _maxConcurrent();
      final active = <Future<void>>{};
      while (!_paused && (_queue.isNotEmpty || active.isNotEmpty)) {
        // Gate new jobs on the current network: when "only over Wi-Fi" is
        // on (or the device is offline) we stop pulling from the queue and
        // surface a waiting-for-network state, mirroring Mihon's
        // downloaderStop. The connectivity listener re-kicks the drain once
        // the network becomes acceptable again.
        final netOk = _queue.isEmpty ? true : await _networkAllowsDownload();
        if (netOk && _networkBlocked) {
          _networkBlocked = false;
          _events.add(const DownloadEvent.queueResumed());
        } else if (!netOk && !_networkBlocked && _queue.isNotEmpty) {
          _networkBlocked = true;
          _events.add(const DownloadEvent.networkWaiting());
        }
        // Top up the in-flight set until we hit the concurrency cap or
        // run out of queued jobs.
        while (!_paused &&
            netOk &&
            _queue.isNotEmpty &&
            active.length < concurrency) {
          final job = _queue.removeAt(0);
          late final Future<void> f;
          f = _runJob(job).whenComplete(() {
            // Keep errored jobs registered so they can be retried; only
            // forget jobs that completed or were cancelled.
            if (!job.errored) _byChapter.remove(job.chapter.id);
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
      // Nothing left running: take the progress notification down. Queued as
      // the final link so a page that posted just before this still loses.
      _queueNotification(
        NotificationService.instance.cancelDownloadProgress,
      );
    }
  }

  Future<void> _runJob(_DownloadJob job) async {
    final manga = job.manga;
    final chapter = job.chapter;
    job.errored = false;
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
      // Download pages with bounded concurrency (Mihon's parallelPageLimit).
      // Files are slotted by index so the CBZ archive stays page-ordered even
      // though completions interleave. The first error stops scheduling new
      // pages, in-flight ones drain, then it is rethrown for the catch below.
      final pageLimit = await _maxPageConcurrent();
      final pageSlots = List<File?>.filled(pages.length, null);
      var completed = 0;
      var nextIndex = 0;
      Object? firstError;
      StackTrace? firstStack;
      final active = <Future<void>>{};
      while (nextIndex < pages.length || active.isNotEmpty) {
        while (firstError == null &&
            nextIndex < pages.length &&
            active.length < pageLimit) {
          final i = nextIndex++;
          late final Future<void> f;
          f = _downloadPage(dir, pages[i], i, job).then((file) {
            pageSlots[i] = file;
            completed++;
            job.downloadedPages = completed;
            _events.add(
              DownloadEvent(
                chapterId: chapter.id,
                state: DownloadState.downloading,
                progress: completed / pages.length,
                downloadedPages: completed,
                totalPages: pages.length,
              ),
            );
            _notifyProgress(job, completed, pages.length);
          }).catchError((Object e, StackTrace s) {
            firstError ??= e;
            firstStack ??= s;
          }).whenComplete(() => active.remove(f));
          active.add(f);
        }
        if (active.isEmpty) break;
        await Future.any(active);
      }
      if (firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }
      final pageFiles = pageSlots.whereType<File>().toList();
      // Optionally archive the chapter into a single CBZ alongside the
      // page folder, mirroring Mihon's `saveChaptersAsCBZ`. The folder is
      // removed once the archive is written so a chapter lives as exactly
      // one of {folder, cbz}, matching Mihon's on-disk shape.
      if (await _saveAsCbz()) {
        await _archiveChapterAsCbz(dir, pageFiles);
      } else {
        await File(p.join(dir.path, '.done')).create();
      }
      _indexAdd(manga.source, manga.id, chapter.id);
      _events.add(
        DownloadEvent(chapterId: chapter.id, state: DownloadState.completed),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // User cancelled the running download — drop the partial chapter
        // directory and forget the job (drain removes it since it isn't
        // flagged errored).
        final dir = await _chapterDir(manga.source, manga.id, chapter.id);
        if (await dir.exists()) await dir.delete(recursive: true);
        _indexRemove(manga.source, manga.id, chapter.id);
        _events.add(
          DownloadEvent(chapterId: chapter.id, state: DownloadState.deleted),
        );
        return;
      }
      job.errored = true;
      _events.add(
        DownloadEvent(
          chapterId: chapter.id,
          state: DownloadState.failed,
          error: e.toString(),
        ),
      );
      // The job stays registered for retry, so the notification is the only
      // sign a background download died — the queue screen may never be open.
      _queueNotification(
        () => NotificationService.instance.showDownloadError(chapter.name),
      );
    } catch (e) {
      job.errored = true;
      _events.add(
        DownloadEvent(
          chapterId: chapter.id,
          state: DownloadState.failed,
          error: e.toString(),
        ),
      );
      // The job stays registered for retry, so the notification is the only
      // sign a background download died — the queue screen may never be open.
      _queueNotification(
        () => NotificationService.instance.showDownloadError(chapter.name),
      );
    }
  }

  /// Downloads one page image into [dir] as a zero-padded, 1-based filename
  /// (`0001.jpg`, …) and returns the target file. Skips the network fetch if
  /// the file already exists (resumable). Honours the job's cancel token.
  Future<File> _downloadPage(
    Directory dir,
    SourcePage page,
    int index,
    _DownloadJob job,
  ) async {
    final imageUrl = page.imageUrl ?? page.url;
    final ext = _extForUrl(imageUrl);
    final target = File(p.join(
      dir.path,
      '${(index + 1).toString().padLeft(4, '0')}.$ext',
    ));
    if (!await target.exists()) {
      // Write to a temp path and rename on success: Dio's deleteOnError only
      // covers request errors, not the process being killed mid-write. A
      // truncated file at the final path would be skipped as "already
      // downloaded" on re-queue and ship a corrupt page under the .done
      // marker; a leftover .part is simply re-downloaded.
      final part = File('${target.path}.part');
      await _dio.download(
        imageUrl,
        part.path,
        options: Options(headers: page.headers),
        cancelToken: job.cancelToken,
      );
      await part.rename(target.path);
    }
    return target;
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
    // Jobs not in the queue are either actively downloading or have
    // errored out (errored jobs are left registered for retry).
    final offQueue = _byChapter.values
        .where((j) => !_queue.contains(j))
        .toList(growable: false);
    return [
      for (final j in offQueue.where((j) => !j.errored))
        ActiveDownload(
          manga: j.manga,
          chapter: j.chapter,
          current: true,
          downloadedPages: j.downloadedPages,
          totalPages: j.totalPages,
        ),
      for (final j in offQueue.where((j) => j.errored))
        ActiveDownload(
          manga: j.manga,
          chapter: j.chapter,
          current: false,
          errored: true,
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

  /// Cancels a download in any state. A queued job is dropped from the
  /// queue; an errored job is forgotten; the currently-running job has its
  /// in-flight image request aborted via its [CancelToken] (the run loop's
  /// cancel branch then emits `deleted` and the drain loop forgets it).
  /// Returns `true` if a matching job was found.
  bool cancel(int chapterId) {
    final job = _byChapter[chapterId];
    if (job == null) return false;
    final idx = _queue.indexOf(job);
    if (idx >= 0) {
      _queue.removeAt(idx);
      _byChapter.remove(chapterId);
      _events.add(
        DownloadEvent(chapterId: chapterId, state: DownloadState.deleted),
      );
      return true;
    }
    if (job.errored) {
      _byChapter.remove(chapterId);
      _events.add(
        DownloadEvent(chapterId: chapterId, state: DownloadState.deleted),
      );
      return true;
    }
    // Currently running — abort in-flight work; cleanup happens in _runJob.
    job.cancelToken.cancel('cancelled by user');
    return true;
  }

  /// Re-queues a previously-errored job with a fresh [CancelToken], moving
  /// it back to the tail of the queue and kicking the drain loop. No-op if
  /// the chapter isn't currently in an errored state. Returns whether a
  /// retry was scheduled.
  bool retry(int chapterId) {
    final job = _byChapter[chapterId];
    if (job == null || !job.errored) return false;
    job.errored = false;
    job.downloadedPages = 0;
    job.cancelToken = CancelToken();
    _queue.add(job);
    _events.add(
      DownloadEvent(chapterId: chapterId, state: DownloadState.queued),
    );
    unawaited(_drain());
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

  /// Sorts the queued jobs in place by [compare] (parity with Kotlin's
  /// DownloadQueueScreen "Sort" menu — by upload date / chapter number,
  /// ascending or descending). The currently-running job is untouched
  /// since it isn't in `_queue`. Emits a `queued` event so the queue
  /// screen repaints.
  void sortQueue(int Function(Chapter a, Chapter b) compare) {
    if (_queue.length < 2) return;
    _queue.sort((a, b) => compare(a.chapter, b.chapter));
    _events.add(
      DownloadEvent(
        chapterId: _queue.first.chapter.id,
        state: DownloadState.queued,
      ),
    );
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
    await _connSub?.cancel();
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
    this.errored = false,
    this.downloadedPages = 0,
    this.totalPages = 0,
  });

  final Manga manga;
  final Chapter chapter;

  /// True if this is the job currently being downloaded; false for
  /// items still waiting in the queue or sitting in an errored state.
  final bool current;

  /// True if this job's last run failed and it's awaiting a retry.
  final bool errored;

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

  /// Set when the last run failed for a reason other than user cancel.
  /// Errored jobs stay registered in `_byChapter` (the drain loop leaves
  /// them) so the queue screen can offer a Retry affordance.
  bool errored = false;

  /// Aborts the in-flight image request when the user cancels a running
  /// download. Replaced with a fresh token by [DownloadRepository.retry].
  CancelToken cancelToken = CancelToken();
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
  // Emitted when the drain loop stalls because the current network doesn't
  // satisfy the "only over Wi-Fi" policy (or the device is offline). The
  // queue screen uses it to show a waiting-for-network banner.
  networkWaiting,
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

  const DownloadEvent.networkWaiting()
      : chapterId = 0,
        state = DownloadState.networkWaiting,
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
