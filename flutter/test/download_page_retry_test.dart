import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/download/download_repository.dart';

/// Kotlin `Downloader.getOrDownloadImage` retries each image three times,
/// waiting 2, 4 and 8 seconds. Without it one dropped connection on page 40 of
/// 60 fails the whole chapter — `_runJob` stops scheduling at the first error —
/// and the user has to retry by hand.
void main() {
  test('a transient failure is retried and the value comes back', () async {
    var calls = 0;
    final waited = <Duration>[];
    final value = await withPageRetries<String>(
      () async {
        calls++;
        if (calls < 3) throw Exception('connection reset');
        return 'page';
      },
      sleep: (d) async => waited.add(d),
    );
    expect(value, 'page');
    expect(calls, 3);
    expect(waited, const [Duration(seconds: 2), Duration(seconds: 4)]);
  });

  test('the fork\'s backoff: 2s, 4s, 8s, then give up', () async {
    var calls = 0;
    final waited = <Duration>[];
    await expectLater(
      withPageRetries<void>(
        () async {
          calls++;
          throw Exception('down');
        },
        sleep: (d) async => waited.add(d),
      ),
      throwsA(isA<Exception>()),
    );
    // Four attempts in all — the first plus three retries.
    expect(calls, 4);
    expect(waited, const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ]);
  });

  test('a fatal error surfaces immediately — a cancel must not wait 14s',
      () async {
    var calls = 0;
    final waited = <Duration>[];
    await expectLater(
      withPageRetries<void>(
        () async {
          calls++;
          throw StateError('cancelled');
        },
        isFatal: (e) => e is StateError,
        sleep: (d) async => waited.add(d),
      ),
      throwsStateError,
    );
    expect(calls, 1);
    expect(waited, isEmpty);
  });

  test('a first-try success never sleeps', () async {
    final waited = <Duration>[];
    expect(
      await withPageRetries<int>(() async => 1, sleep: (d) async {
        waited.add(d);
      }),
      1,
    );
    expect(waited, isEmpty);
  });
}
