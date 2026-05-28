import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  final _events = StreamController<DownloadEvent>.broadcast();
  Stream<DownloadEvent> get events => _events.stream;

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
        .where((e) => e is File && p.basename(e.path) != '.done')
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
    final dir = await _chapterDir(sourceId, mangaId, chapterId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _events.add(
      DownloadEvent(chapterId: chapterId, state: DownloadState.deleted),
    );
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

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        await _runJob(job);
        _byChapter.remove(job.chapter.id);
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
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final imageUrl = page.imageUrl ?? page.url;
        final ext = _extForUrl(imageUrl);
        final target = File(p.join(
          dir.path,
          '${(i + 1).toString().padLeft(4, '0')}.$ext',
        ));
        if (await target.exists()) continue;
        await _dio.download(
          imageUrl,
          target.path,
          options: Options(headers: page.headers),
        );
        _events.add(
          DownloadEvent(
            chapterId: chapter.id,
            state: DownloadState.downloading,
            progress: (i + 1) / pages.length,
          ),
        );
      }
      await File(p.join(dir.path, '.done')).create();
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

  Future<void> close() async {
    await _events.close();
  }
}

class _DownloadJob {
  _DownloadJob({required this.manga, required this.chapter});
  final Manga manga;
  final Chapter chapter;
}

enum DownloadState { queued, downloading, completed, failed, deleted }

class DownloadEvent {
  const DownloadEvent({
    required this.chapterId,
    required this.state,
    this.progress,
    this.error,
  });

  final int chapterId;
  final DownloadState state;
  final double? progress;
  final String? error;
}

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  final ext = ref.watch(extensionRepositoryProvider);
  final http = ref.watch(appHttpClientProvider);
  return DownloadRepository(ext, http);
});
