import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mohyeong/data/source/source_icon.dart';
import 'package:mohyeong/presentation/tide/tide.dart';

/// The two fiddly halves of resolving a source's logo: deciding which of the
/// icons a page declares is worth fetching, and deciding whether what came
/// back is actually an image. Both are pure, and both are the kind of thing
/// that fails silently — a wrong answer here just leaves a blank tile.

Uint8List _bytes(List<int> head, {int pad = 32}) =>
    Uint8List.fromList([...head, ...List<int>.filled(pad, 0)]);

/// A one-entry ICO whose payload is [payload], at the standard 22-byte offset.
Uint8List _ico(List<int> payload) {
  final header = ByteData(22);
  header.setUint16(0, 0, Endian.little); // reserved
  header.setUint16(2, 1, Endian.little); // type: icon
  header.setUint16(4, 1, Endian.little); // one entry
  header.setUint32(14, payload.length, Endian.little);
  header.setUint32(18, 22, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);
}

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  group('iconLinksIn', () {
    final origin = Uri.parse('https://example.com/');

    test('an apple-touch-icon outranks a plain icon', () {
      final links = SourceIconStore.iconLinksIn('''
        <html><head>
          <link rel="icon" href="/favicon-16.png" sizes="16x16">
          <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
        </head><body></body></html>
      ''', origin);

      expect(links.first, Uri.parse('https://example.com/touch.png'));
      expect(links, hasLength(2));
    });

    test('among peers, the largest declared size wins', () {
      final links = SourceIconStore.iconLinksIn('''
        <head>
          <link rel="icon" href="/small.png" sizes="16x16">
          <link rel="icon" href="/big.png" sizes="192x192">
          <link rel="icon" href="/mid.png" sizes="48x48">
        </head>
      ''', origin);

      expect(links.map((u) => u.path), ['/big.png', '/mid.png', '/small.png']);
    });

    test('a sizes attribute too long to be a number does not throw', () {
      // Straight out of a stranger's markup: `\d+` is unbounded, and
      // `int.parse` throws on a digit run past what fits in 64 bits.
      final links = SourceIconStore.iconLinksIn('''
        <head>
          <link rel="icon" href="/junk.png" sizes="99999999999999999999x16">
          <link rel="icon" href="/real.png" sizes="64x64">
        </head>
      ''', origin);

      // The junk size is ignored rather than fatal, so the sized icon wins
      // and the unsized one still appears.
      expect(links.map((u) => u.path), ['/real.png', '/junk.png']);
    });

    test('an absurd size cannot overflow its way to the front', () {
      // A value that parses but whose product wraps negative would sort a
      // huge icon LAST; anything past a plausible icon edge is not a size.
      final links = SourceIconStore.iconLinksIn('''
        <head>
          <link rel="icon" href="/absurd.png" sizes="4000000000x4000000000">
          <link rel="icon" href="/real.png" sizes="64x64">
        </head>
      ''', origin);

      expect(links.map((u) => u.path), ['/real.png', '/absurd.png']);
    });

    test('equally-ranked unsized icons keep a stable order', () {
      final html = '''
        <head>
          <link rel="icon" href="/c.png">
          <link rel="icon" href="/a.png">
          <link rel="icon" href="/b.png">
        </head>
      ''';
      expect(
        SourceIconStore.iconLinksIn(html, origin).map((u) => u.path),
        ['/a.png', '/b.png', '/c.png'],
      );
    });

    test('skips what the engine cannot paint', () {
      final links = SourceIconStore.iconLinksIn('''
        <head>
          <link rel="icon" href="/logo.svg">
          <link rel="icon" href="data:image/png;base64,AAAA">
          <link rel="stylesheet" href="/site.css">
          <link rel="icon" href="/real.png">
        </head>
      ''', origin);

      expect(links.map((u) => u.path), ['/real.png']);
    });

    test('resolves relative, absolute and protocol-relative hrefs', () {
      final links = SourceIconStore.iconLinksIn('''
        <head>
          <link rel="icon" href="assets/a.png" sizes="64x64">
          <link rel="icon" href="//cdn.example.net/b.png" sizes="48x48">
          <link rel='icon' href='https://other.example/c.png' sizes="32x32">
        </head>
      ''', Uri.parse('https://example.com/browse/'));

      expect(links.map((u) => u.toString()), [
        'https://example.com/browse/assets/a.png',
        'https://cdn.example.net/b.png',
        'https://other.example/c.png',
      ]);
    });

    test('ignores link tags in the body', () {
      final links = SourceIconStore.iconLinksIn(
        '<head><link rel="icon" href="/head.png"></head>'
        '<body><link rel="icon" href="/body.png"></body>',
        origin,
      );

      expect(links.map((u) => u.path), ['/head.png']);
    });
  });

  group('sniffImage', () {
    test('recognises the formats the engine decodes', () {
      expect(SourceIconStore.sniffImage(_bytes(_png))?.extension, 'png');
      expect(
        SourceIconStore.sniffImage(_bytes([0xFF, 0xD8, 0xFF, 0xE0]))?.extension,
        'jpg',
      );
      expect(
        SourceIconStore.sniffImage(_bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))
            ?.extension,
        'gif',
      );
      expect(
        SourceIconStore.sniffImage(Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0, 0, 0, 0, //            size
          0x57, 0x45, 0x42, 0x50, // WEBP
          ...List<int>.filled(16, 0),
        ]))?.extension,
        'webp',
      );
    });

    test('rejects the HTML error page a missing favicon.ico returns', () {
      final html = Uint8List.fromList('<!DOCTYPE html><html>404'.codeUnits);
      expect(SourceIconStore.sniffImage(html), isNull);
    });

    test('unwraps the PNG inside an .ico', () {
      final payload = [..._png, 1, 2, 3, 4];
      final result = SourceIconStore.sniffImage(_ico(payload));

      expect(result?.extension, 'png');
      expect(result?.bytes, payload);
    });

    test('leaves a BMP-only .ico alone — that would need a real decoder', () {
      // A classic ICO entry: a BITMAPINFOHEADER (size 40) rather than a PNG.
      final bmpEntry = [40, 0, 0, 0, ...List<int>.filled(24, 0)];
      expect(SourceIconStore.sniffImage(_ico(bmpEntry)), isNull);
    });
  });

  group('tideSourceHost', () {
    test('strips the scheme and a leading www', () {
      expect(tideSourceHost('https://www.asuracomic.net/'), 'asuracomic.net');
      expect(tideSourceHost('https://mangadex.org'), 'mangadex.org');
    });

    test('is null when there is nothing to show', () {
      expect(tideSourceHost(null), isNull);
      expect(tideSourceHost(''), isNull);
      expect(tideSourceHost('not a url'), isNull);
    });
  });
}
