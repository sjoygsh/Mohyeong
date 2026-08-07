import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/source/js/js_runtime.dart';
import '../../data/sync/sync_transport.dart';
import '../../data/track/tracker.dart';
import '../../domain/chapter/model/no_chapters_exception.dart';

/// Turns a caught error into a sentence worth showing someone.
///
/// Screens used to interpolate the exception straight into the toast
/// (`'Refresh failed: $e'`), which put things like
/// `DioException [connection error]: SocketException: Failed host lookup` in
/// front of a reader. The detail is the one part that can't help them: they
/// can't act on it, and it reads like the app broke rather than the network.
///
/// Types that carry a message written FOR a person keep it — [TrackerException]
/// and [SyncException] are raised by our own code with wording already aimed at
/// the UI. Everything else is classified by what the user could do about it,
/// and the raw error goes to the debug console instead, where it belongs.
///
/// [fallback] is the caller's own context ("Couldn't save this page") and is
/// used whenever the error itself says nothing useful — so the message keeps
/// naming the action that failed even when the cause is unrecognised.
String userMessage(Object error, {String fallback = 'Something went wrong.'}) {
  final message = _classify(error, fallback);
  if (kDebugMode) {
    debugPrint('surfaced to user as "$message": $error');
  }
  return message;
}

String _classify(Object error, String fallback) {
  // Our own exceptions are already phrased for a person.
  if (error is TrackerNotAuthenticated) return 'Sign in to that tracker first.';
  if (error is TrackerException) return error.message;
  if (error is SyncException) return error.message;
  if (error is NoChaptersException) return 'This source returned no chapters.';

  // A refused or broken REQUEST, before anything is blamed on the extension.
  //
  // This has to come first because the JS bridge raises HTTP failures as
  // `Error('HTTP 403 for <url>')`, which arrives here as a
  // [JsRuntimeException] — so every Cloudflare wall and every dead origin used
  // to read as "this source's extension failed to run", which blames the one
  // part that worked. These are also the app's most common real failures:
  // 403 from a CDN that fingerprint-blocks non-browser TLS, and Cloudflare's
  // 52x family when a site's own server is down.
  final status = _httpStatus(error);
  if (status != null) {
    if (status == 401 || status == 403) {
      return 'This source is refusing the app right now.';
    }
    if (status == 404) return 'That page is gone from the source.';
    if (status == 429) return 'The source is rate-limiting — wait a moment.';
    if (status >= 500) return 'The source’s own server is down.';
  }

  // The extension misbehaved — not something the reader can fix, but saying
  // WHICH half broke stops it reading as a bug in the app.
  if (error is JsRuntimeException) {
    return 'This source’s extension failed to run.';
  }

  // Reachability. Dio wraps these, so check the chain rather than the type:
  // presentation has no dio dependency and should not grow one for a string.
  if (_looksLikeNetwork(error)) {
    return 'Couldn’t reach the source. Check your connection.';
  }
  if (error is TimeoutException) return 'That took too long — try again.';

  // The source replied with something unparseable. Common when a site changes
  // its markup, and worth distinguishing from being offline.
  if (error is FormatException) {
    return 'This source sent something unexpected.';
  }

  if (error is FileSystemException) {
    return 'Couldn’t read or write that file.';
  }

  return fallback;
}

/// The HTTP status an error is reporting, or null when it isn't reporting one.
///
/// Read out of the message rather than off a type, for the same reason
/// [_looksLikeNetwork] does: the two producers phrase it differently and
/// neither type is visible from here. The JS bridge throws
/// `Error('HTTP 503 for <url>')`; Dio writes
/// `... status code of 403`. Only 100–599 counts, so a chapter URL that
/// happens to contain "HTTP 1234" can't be mistaken for one.
int? _httpStatus(Object error) {
  final text = error.toString();
  final m = RegExp(r'(?:HTTP|status code of)\s+(\d{3})\b').firstMatch(text);
  if (m == null) return null;
  final code = int.tryParse(m.group(1)!);
  if (code == null || code < 100 || code > 599) return null;
  return code;
}

/// True for the socket/HTTP families, including when they're wrapped (Dio
/// nests the original in its own message).
bool _looksLikeNetwork(Object error) {
  if (error is SocketException || error is HttpException) return true;
  if (error is HandshakeException || error is TlsException) return true;
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection closed') ||
      text.contains('connection error');
}
