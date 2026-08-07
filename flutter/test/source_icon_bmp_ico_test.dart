import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/source/source_icon.dart';

/// Skia has no ICO decoder. The PNG-in-ICO case was already sliced out, but the
/// older BMP-with-mask form was left alone — and that is not exotic: tapas.io,
/// a working source, ships exactly one 32bpp BMP entry and so had no logo.
///
/// The catch that makes it a decode rather than a slice: a DIB inside an ICO
/// declares DOUBLE its real height, because an AND mask follows the colour
/// data. Hand those bytes to anything as a `.bmp` and you get a stretched image
/// with garbage in the bottom half.

/// A single-entry .ico holding an uncompressed BGRA DIB.
Uint8List bmpIco(int size, {int bits = 32}) {
  final bytesPerPixel = bits ~/ 8;
  final stride = ((size * bytesPerPixel + 3) ~/ 4) * 4;
  final maskStride = ((size + 31) ~/ 32) * 4;
  final dib = BytesBuilder();

  final header = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, size, Endian.little)
    ..setInt32(8, size * 2, Endian.little) // doubled, per the format
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bits, Endian.little)
    ..setUint32(16, 0, Endian.little); // BI_RGB
  dib.add(header.buffer.asUint8List());

  // Bottom-up rows. Row 0 of the FILE is the BOTTOM row of the image, so
  // colour it distinctly to prove the flip happens.
  final rows = Uint8List(stride * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final at = y * stride + x * bytesPerPixel;
      final bottom = y == 0;
      rows[at] = bottom ? 0 : 255; // B
      rows[at + 1] = 0; // G
      rows[at + 2] = bottom ? 255 : 0; // R
      if (bytesPerPixel == 4) rows[at + 3] = 255; // A
    }
  }
  dib.add(rows);
  dib.add(Uint8List(maskStride * size)); // AND mask

  final body = dib.toBytes();
  final out = BytesBuilder();
  final head = ByteData(6)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 1, Endian.little);
  out.add(head.buffer.asUint8List());
  final entry = ByteData(16)
    ..setUint8(0, size)
    ..setUint8(1, size)
    ..setUint16(4, 1, Endian.little)
    ..setUint16(6, bits, Endian.little)
    ..setUint32(8, body.length, Endian.little)
    ..setUint32(12, 22, Endian.little);
  out.add(entry.buffer.asUint8List());
  out.add(body);
  return out.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 32bpp BMP icon becomes a PNG the engine can actually decode',
      () async {
    final sniffed = SourceIconStore.sniffImage(bmpIco(32));
    expect(sniffed, isNotNull);
    expect(sniffed!.extension, 'png');
    expect(sniffed.bytes.sublist(0, 8),
        const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    // The real assertion: Skia takes it. A hand-rolled PNG with a bad CRC or a
    // mis-sized IDAT would sniff fine and still be unpaintable, which is the
    // exact failure this whole thing exists to remove.
    final codec = await ui.instantiateImageCodec(sniffed.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 32);
    // Half the DECLARED height — the AND mask must not become picture.
    expect(frame.image.height, 32);
  });

  test('24bpp works too, and comes out opaque', () async {
    final sniffed = SourceIconStore.sniffImage(bmpIco(16, bits: 24));
    expect(sniffed, isNotNull);
    final codec = await ui.instantiateImageCodec(sniffed!.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 16);
    expect(frame.image.height, 16);

    final data = await frame.image.toByteData();
    expect(data!.getUint8(3), 255, reason: '24bpp has no alpha channel to read');
  });

  test('the image is not upside down', () async {
    // The bottom file-row was painted red; after the flip it must be the
    // BOTTOM of the image, not the top.
    final sniffed = SourceIconStore.sniffImage(bmpIco(4));
    final codec = await ui.instantiateImageCodec(sniffed!.bytes);
    final frame = await codec.getNextFrame();
    final px = await frame.image.toByteData();

    int red(int x, int y) => px!.getUint8((y * 4 + x) * 4);
    expect(red(0, 3), 255, reason: 'bottom row is the red one');
    expect(red(0, 0), 0, reason: 'top row is the blue one');
  });

  test('a PNG-carrying ico still takes the slice path, not the decoder', () {
    // Cheapest possible proof the ordering did not change: a real PNG payload
    // comes back byte-identical rather than re-encoded.
    final png = SourceIconStore.sniffImage(bmpIco(8))!.bytes;
    final out = BytesBuilder();
    final head = ByteData(6)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, 1, Endian.little);
    out.add(head.buffer.asUint8List());
    final entry = ByteData(16)
      ..setUint8(0, 8)
      ..setUint8(1, 8)
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, 22, Endian.little);
    out.add(entry.buffer.asUint8List());
    out.add(png);

    final sniffed = SourceIconStore.sniffImage(out.toBytes());
    expect(sniffed!.bytes, png);
  });

  test('a palletised or compressed entry is refused rather than guessed', () {
    final ico = bmpIco(16);
    // Flip BI_RGB to BI_RLE8 in the DIB header (entry data starts at 22).
    ico.buffer.asByteData().setUint32(22 + 16, 1, Endian.little);
    expect(SourceIconStore.sniffImage(ico), isNull);
  });
}
