import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/download/download_repository.dart';
import 'package:mohyeong/data/network/app_http_client.dart';
import 'package:mohyeong/data/source/extension_repository.dart';
import 'package:mohyeong/data/source/installed_extension.dart';
import 'package:mohyeong/data/source/local_source_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `syncChaptersWithSource` prunes rows the source stopped returning, and
/// collapses duplicate rows onto one canonical row. Neither touched the
/// filesystem, so those chapters' pages stayed on disk forever — counting in
/// the storage total and keeping the manga in the Downloaded filter with
/// chapters that can never open.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;

  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late DownloadRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    support = Directory.systemTemp.createTempSync('mohyeong_dl');
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    final http = await AppHttpClient.instance();
    final prefs = await SharedPreferences.getInstance();
    repo = DownloadRepository(
      ExtensionRepository(
        await ExtensionStorage.create(),
        http,
        LocalSourcePreferences(prefs),
      ),
      http,
    );
  });

  tearDown(() async {
    await repo.close();
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  Directory chapterDir(int source, int manga, int chapter) {
    final dir = Directory(p.join(
      support.path,
      'downloads',
      '$source',
      '$manga',
      '$chapter',
    ))
      ..createSync(recursive: true);
    File(p.join(dir.path, '0001.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(dir.path, '.done')).writeAsStringSync('');
    return dir;
  }

  test('a chapter directory with no row left is reclaimed', () async {
    final live = chapterDir(7, 1, 100);
    final orphan = chapterDir(7, 1, 101);
    final otherOrphan = chapterDir(9, 2, 202);

    final removed = await repo.pruneOrphanedDownloads({100});

    expect(removed, 2);
    expect(live.existsSync(), isTrue, reason: 'a live chapter must survive');
    expect(orphan.existsSync(), isFalse);
    expect(otherOrphan.existsSync(), isFalse);
  });

  test('the storage total stops counting what was reclaimed', () async {
    chapterDir(7, 1, 100);
    chapterDir(7, 1, 101);
    expect(await repo.totalDownloadedCount(), 2);

    await repo.pruneOrphanedDownloads({100});

    // Rebuilt from disk — the stale index would still say 2.
    expect(await repo.totalDownloadedCount(), 1);
  });

  test('an empty id set means "I do not know" and deletes nothing', () async {
    // A failed or half-built query must never wipe the library's downloads.
    final kept = chapterDir(7, 1, 100);
    expect(await repo.pruneOrphanedDownloads(const <int>{}), 0);
    expect(kept.existsSync(), isTrue);
  });

  test('nothing downloaded at all is not an error', () async {
    expect(await repo.pruneOrphanedDownloads({1, 2, 3}), 0);
  });
}
