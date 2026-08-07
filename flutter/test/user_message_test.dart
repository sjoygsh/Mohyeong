import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/source/js/js_runtime.dart';
import 'package:mohyeong/domain/chapter/model/no_chapters_exception.dart';
import 'package:mohyeong/presentation/util/user_message.dart';

/// What a reader is told when a source fails.
///
/// The case that matters most: the JS bridge raises HTTP failures as
/// `Error('HTTP 403 for <url>')`, which reaches `userMessage` as a
/// [JsRuntimeException]. Classified on type alone that reads as "this source's
/// extension failed to run" — blaming the one part that worked — and a
/// Cloudflare wall or a dead origin is the app's most common real failure.
void main() {
  group('HTTP status is read before the extension is blamed', () {
    test('a fingerprint-walled CDN says the source is refusing us', () {
      expect(
        userMessage(JsRuntimeException('HTTP 403 for https://site.example/x')),
        'This source is refusing the app right now.',
      );
    });

    test('Cloudflare 52x says the site is down, not that we broke', () {
      for (final code in [520, 521, 522, 525]) {
        expect(
          userMessage(JsRuntimeException('HTTP $code for https://s.example')),
          'The source’s own server is down.',
          reason: 'HTTP $code',
        );
      }
    });

    test('404 and 429 each say their own thing', () {
      expect(userMessage(JsRuntimeException('HTTP 404 for https://s.example')),
          'That page is gone from the source.');
      expect(userMessage(JsRuntimeException('HTTP 429')),
          'The source is rate-limiting — wait a moment.');
    });

    test("Dio's own phrasing is understood too", () {
      // Presentation has no dio dependency, so this is matched by wording.
      expect(
        userMessage(StateError(
            'DioException [bad response]: The request returned an invalid '
            'status code of 503.')),
        'The source’s own server is down.',
      );
    });

    test('a real script error still blames the extension', () {
      expect(
        userMessage(JsRuntimeException('TypeError: x is not a function')),
        'This source’s extension failed to run.',
      );
    });

    test('a number that is not a status is not treated as one', () {
      // A chapter URL can carry any digits; only 100-599 after HTTP counts.
      expect(
        userMessage(JsRuntimeException('parse failed at HTTP 1234 marker'),
            fallback: 'Couldn\'t load that chapter.'),
        'This source’s extension failed to run.',
      );
    });
  });

  group('the classifications that were already there still hold', () {
    test('no network', () {
      expect(
        userMessage(const SocketException('Failed host lookup')),
        'Couldn’t reach the source. Check your connection.',
      );
    });

    test('timeout', () {
      expect(userMessage(TimeoutException('slow')),
          'That took too long — try again.');
    });

    test('unparseable response', () {
      expect(userMessage(const FormatException('bad')),
          'This source sent something unexpected.');
    });

    test('no chapters', () {
      expect(userMessage(const NoChaptersException()),
          'This source returned no chapters.');
    });

    test('anything unrecognised keeps the caller\'s own wording', () {
      expect(
        userMessage(StateError('something odd'),
            fallback: 'Couldn\'t refresh the library.'),
        'Couldn\'t refresh the library.',
      );
    });
  });
}
