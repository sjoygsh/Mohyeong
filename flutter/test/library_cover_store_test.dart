import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mohyeong/data/cover/cover_cache.dart';

/// Library covers used to live only in the image cache shared with reader
/// pages (30-day expiry, 2000 files), so they kept disappearing and loading
/// again. Mihon keeps them in their own store; these pin that store's rules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late CoverCache covers;
  const url = 'https://aquareader.org/wp-content/uploads/cover.webp';

  setUp(() {
    root = Directory.systemTemp.createTempSync('covers');
    Directory(p.join(root.path, 'custom')).createSync();
    covers = CoverCache.forTesting(root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('named by the md5 of the thumbnail url, as Mihon names it', () {
    expect(
      p.basename(covers.libraryCoverPath(url)),
      // md5 of the url above.
      matches(RegExp(r'^[0-9a-f]{32}$')),
    );
    expect(covers.libraryCoverPath(url), isNot(covers.libraryCoverPath('$url?2')));
  });

  test('only a library series with a web cover is saved', () {
    expect(covers.libraryCoverTarget(1, url, favorite: false), isNull);
    expect(covers.libraryCoverTarget(1, null, favorite: true), isNull);
    expect(covers.libraryCoverTarget(1, '/local/cover.jpg', favorite: true),
        isNull);
    expect(covers.libraryCoverTarget(1, url, favorite: true),
        covers.libraryCoverPath(url));
  });

  test('a stored cover is served from disk, and not saved twice', () async {
    final target = covers.libraryCoverTarget(1, url, favorite: true)!;
    await storeLibraryCover(target, bytes: Uint8List.fromList([1, 2, 3]));
    expect(File(target).readAsBytesSync(), [1, 2, 3]);
    expect(File('$target.part').existsSync(), isFalse);

    // A fresh lookup (what the next launch does) finds it.
    final next = CoverCache.forTesting(root.path);
    expect(next.coverUrlFor(1, url), target);
    expect(next.libraryCoverTarget(1, url, favorite: true), isNull);
  });

  test('saving copies the file it loaded from', () async {
    final source = File(p.join(root.path, 'downloaded.webp'))
      ..writeAsBytesSync([9, 9]);
    final target = covers.libraryCoverPath(url);
    await storeLibraryCover(target, fromPath: source.path);
    expect(File(target).readAsBytesSync(), [9, 9]);
    expect(source.existsSync(), isTrue, reason: 'a copy, not a move');
  });

  test('a failed save leaves nothing half-written behind', () async {
    final target = covers.libraryCoverPath(url);
    await storeLibraryCover(target, fromPath: p.join(root.path, 'missing'));
    expect(File(target).existsSync(), isFalse);
    expect(File('$target.part').existsSync(), isFalse);
  });

  test('a custom cover still wins over the stored one', () async {
    final target = covers.libraryCoverPath(url);
    await storeLibraryCover(target, bytes: Uint8List.fromList([1]));
    await covers.setCustomCover(7, Uint8List.fromList([2]));
    expect(covers.coverUrlFor(7, url), covers.customCoverFile(7).path);
    expect(covers.libraryCoverTarget(7, url, favorite: true), isNull);
  });

  test('leaving the library removes both covers (Mihon removeCovers)',
      () async {
    final target = covers.libraryCoverPath(url);
    await storeLibraryCover(target, bytes: Uint8List.fromList([1]));
    await covers.setCustomCover(7, Uint8List.fromList([2]));
    await covers.removeCovers(7, url);
    expect(File(target).existsSync(), isFalse);
    expect(covers.customCoverFile(7).existsSync(), isFalse);
    expect(covers.coverUrlFor(7, url), url);
  });

  test('clearing drops library covers but keeps custom ones', () async {
    await storeLibraryCover(covers.libraryCoverPath(url),
        bytes: Uint8List.fromList([1]));
    await storeLibraryCover(covers.libraryCoverPath('$url?b'),
        bytes: Uint8List.fromList([1]));
    await covers.setCustomCover(7, Uint8List.fromList([2]));
    expect(await covers.clearLibraryCovers(), 2);
    expect(covers.customCoverFile(7).existsSync(), isTrue);
    expect(covers.coverUrlFor(1, url), url);
  });
}
