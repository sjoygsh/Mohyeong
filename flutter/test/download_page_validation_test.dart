import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/download/download_repository.dart';

/// A downloaded page that is not an image must not be accepted.
///
/// The failure this guards is silent by construction: an HTML interstitial
/// served under HTTP 200 makes the download SUCCEED, so no retry fires, the
/// chapter is marked done, and a re-queue skips the bad file because it
/// exists. The header check is the only thing standing between that and a
/// permanently broken page.
void main() {
  group('looksLikeImageHeader', () {
    test('accepts the formats the engine can paint', () {
      expect(
        DownloadRepository.looksLikeImageHeader(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        ),
        isTrue,
        reason: 'PNG',
      );
      expect(
        DownloadRepository.looksLikeImageHeader([0xFF, 0xD8, 0xFF, 0xE0]),
        isTrue,
        reason: 'JPEG',
      );
      expect(
        DownloadRepository.looksLikeImageHeader(
          [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
        ),
        isTrue,
        reason: 'GIF89a',
      );
      expect(
        DownloadRepository.looksLikeImageHeader([0x42, 0x4D, 0x36, 0x00]),
        isTrue,
        reason: 'BMP',
      );
      expect(
        DownloadRepository.looksLikeImageHeader([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0x00, 0x00, 0x00, 0x00, // size
          0x57, 0x45, 0x42, 0x50, // WEBP
        ]),
        isTrue,
        reason: 'WebP',
      );
      expect(
        DownloadRepository.looksLikeImageHeader([
          0x00, 0x00, 0x00, 0x20, //
          0x66, 0x74, 0x79, 0x70, // ftyp
          0x61, 0x76, 0x69, 0x66, // avif
        ]),
        isTrue,
        reason: 'AVIF / ISO-BMFF',
      );
    });

    test('rejects an HTML error page served under a 200', () {
      // '<!DOCTYPE h'
      expect(
        DownloadRepository.looksLikeImageHeader(
          '<!DOCTYPE html><html>'.codeUnits,
        ),
        isFalse,
      );
      // The Cloudflare interstitial the HTTP bridge warns about.
      expect(
        DownloadRepository.looksLikeImageHeader(
          '<html><head><title>Just a moment'.codeUnits,
        ),
        isFalse,
      );
    });

    test('rejects an empty or truncated body rather than guessing', () {
      expect(DownloadRepository.looksLikeImageHeader(const []), isFalse);
      expect(DownloadRepository.looksLikeImageHeader(const [0x89]), isFalse);
      // RIFF without the WEBP brand is some other RIFF container.
      expect(
        DownloadRepository.looksLikeImageHeader([
          0x52, 0x49, 0x46, 0x46, //
          0x00, 0x00, 0x00, 0x00,
          0x41, 0x56, 0x49, 0x20, // 'AVI '
        ]),
        isFalse,
      );
    });
  });
}
