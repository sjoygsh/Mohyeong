import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/source/source_id.dart';

void main() {
  group('sourceNumericId', () {
    test('numeric strings pass through unchanged', () {
      // Existing library rows store the source id as its decimal string;
      // these must resolve to the exact same int so installed sources and
      // saved manga keep matching after this change.
      expect(sourceNumericId('0'), 0);
      expect(
        sourceNumericId('2499283573021220255'),
        2499283573021220255,
      );
    });

    test('matches Mihon HttpSource.generateId (MD5, first 64 bits, '
        'sign bit cleared)', () {
      // Kotlin: MD5("mangadex/en/1") -> first 8 bytes big-endian & MAX_VALUE.
      // Verified against the device: a manga added from this source stores
      // exactly this value in mangas.source.
      expect(sourceNumericId('mangadex/en/1'), 2499283573021220255);
    });

    test('non-numeric slugs hash deterministically and stay non-negative', () {
      final a = sourceNumericId('test source/en/1');
      final b = sourceNumericId('test source/en/1');
      expect(a, b);
      expect(a, isNonNegative);
      expect(a, 2128163661150998060);
    });
  });
}
