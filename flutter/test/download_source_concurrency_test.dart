import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/download/download_repository.dart';

/// `download_parallel_source_limit` caps SOURCES, not chapters: Kotlin
/// `Downloader.launchDownloaderJob` groups the queue by source, takes that many
/// groups and starts only the first job of each. The drain loop here used to
/// pull the queue flat, so "download next 10" — ten chapters of one manga —
/// put five chapters times five pages against one host at once.
///
/// [nextStartableDownloadIndex] is the picker that enforces it. -1 means every
/// queued job's source is already busy and the loop must wait for a completion
/// rather than start anything.
void main() {
  test('nothing in flight: the head of the queue starts', () {
    expect(nextStartableDownloadIndex([7, 7, 7], <int>{}), 0);
  });

  test('a source with a chapter in flight is skipped over', () {
    // Ten chapters of one manga: with source 7 busy there is nothing to start.
    expect(nextStartableDownloadIndex(List.filled(10, 7), {7}), -1);
  });

  test('it skips to the first job of an idle source, keeping queue order', () {
    // Queue: three of source 7 (busy), then 9, then 9 again.
    expect(nextStartableDownloadIndex([7, 7, 7, 9, 9], {7}), 3);
  });

  test('FIFO within a source is preserved — never the later duplicate', () {
    expect(nextStartableDownloadIndex([4, 9, 4, 9], {9}), 0);
  });

  test('several busy sources are all skipped', () {
    expect(nextStartableDownloadIndex([1, 2, 3, 4], {1, 2, 3}), 3);
    expect(nextStartableDownloadIndex([1, 2, 3], {1, 2, 3}), -1);
  });

  test('an empty queue has nothing to start', () {
    expect(nextStartableDownloadIndex(const <int>[], <int>{}), -1);
  });
}
