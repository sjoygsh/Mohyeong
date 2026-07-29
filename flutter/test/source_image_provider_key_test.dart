import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/presentation/common/crop_borders_image.dart';
import 'package:mohyeong/presentation/common/source_image.dart';

void main() {
  // The reader's decode economy hinges on every consumer of a page URL
  // resolving the SAME ImageCache key: the displaying widget, precache,
  // the aspect probe, the crop/rotate decorators and the split halves all
  // build providers independently, and a key mismatch decodes the page
  // twice (or re-runs the crop per rebuild). These tests pin the value-
  // equality contract of SourceImage.providerFor and the decorators.
  group('SourceImage.providerFor key identity', () {
    test('same url + config resolve equal providers', () {
      final a = SourceImage.providerFor(
        'https://example.com/page1.jpg',
        headers: const {'Referer': 'https://example.com/'},
        cacheWidth: 2160,
        fullResolution: true,
      );
      final b = SourceImage.providerFor(
        'https://example.com/page1.jpg',
        headers: const {'Referer': 'https://example.com/'},
        cacheWidth: 2160,
        fullResolution: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('fullResolution is part of the key', () {
      final page = SourceImage.providerFor(
        'https://example.com/page1.jpg',
        fullResolution: true,
      );
      final cover = SourceImage.providerFor('https://example.com/page1.jpg');
      expect(page, isNot(equals(cover)));
    });

    test('cacheWidth is part of the key', () {
      final capped = SourceImage.providerFor(
        'https://example.com/page1.jpg',
        cacheWidth: 2160,
      );
      final uncapped =
          SourceImage.providerFor('https://example.com/page1.jpg');
      expect(capped, isNot(equals(uncapped)));
    });

    test('local file paths key equal with the cap applied', () {
      final a = SourceImage.providerFor('/tmp/pages/001.jpg', cacheWidth: 2160);
      final b = SourceImage.providerFor('/tmp/pages/001.jpg', cacheWidth: 2160);
      expect(a, equals(b));
    });
  });

  group('decorator providers preserve inner value equality', () {
    test('crop decorator over capped providers keys equal', () {
      final a = CropBordersImageProvider(SourceImage.providerFor(
        'https://example.com/page1.jpg',
        cacheWidth: 2160,
        fullResolution: true,
      ));
      final b = CropBordersImageProvider(SourceImage.providerFor(
        'https://example.com/page1.jpg',
        cacheWidth: 2160,
        fullResolution: true,
      ));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('half-page decorator keys equal per side over capped providers', () {
      HalfPageImageProvider half({required bool left}) =>
          HalfPageImageProvider(
            SourceImage.providerFor(
              'https://example.com/spread.jpg',
              cacheWidth: 2160,
              fullResolution: true,
            ),
            leftHalf: left,
          );
      expect(half(left: true), equals(half(left: true)));
      expect(half(left: true), isNot(equals(half(left: false))));
    });
  });
}
