import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/credentials_login_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// Komga tracker — points at the user's self-hosted Komga server.
///
/// Auth is HTTP Basic against the configured server URL. The server URL
/// goes into the credential userdata field; the basic-auth header value
/// (already base64-encoded) goes into the access token slot so a single
/// secure-storage read produces a ready-to-attach header.
///
/// In Mihon, Komga is an "enhanced" tracker bound to a Komga source
/// extension — credentials are inherited from the source. Mohyeong's
/// source extension layer hasn't shipped yet, so this implementation is
/// standalone: the user configures the tracker directly, with the
/// server URL captured at login time.
class KomgaTracker extends Tracker {
  KomgaTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(
          TrackerIds.komga,
          'Komga',
          TrackerCategory.advanced,
        );

  // Komga uses three statuses; map them onto the Mihon canonical codes.
  static const int _komgaUnread = 1;
  static const int _komgaReading = 2;
  static const int _komgaCompleted = 3;

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  bool get supportsServerUrl => true;

  @override
  Future<bool> get isLoggedIn => credentials.isAuthenticated(TrackerIds.komga);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('KomgaTracker.dio not attached');
    return d;
  }

  @override
  Future<void> login() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      throw StateError('No navigator available to drive the login flow.');
    }
    final result = await Navigator.of(ctx).push<CredentialsLoginResult?>(
      MaterialPageRoute<CredentialsLoginResult?>(
        builder: (_) => const CredentialsLoginScreen(
          title: 'Log in to Komga',
          includeServerUrl: true,
          serverUrlLabel: 'Komga server URL',
          serverUrlHint: 'https://komga.example.com',
          helperText:
              'Enter your Komga server URL and the username/password '
              'you use to sign in to the web UI.',
        ),
      ),
    );
    if (result == null) {
      throw TrackerException('Komga login cancelled');
    }
    final server = result.serverUrl?.trim() ?? '';
    if (server.isEmpty ||
        result.username.isEmpty ||
        result.password.isEmpty) {
      throw TrackerException(
        'Komga login: server URL, username, and password are required',
      );
    }
    final normalised = _stripTrailingSlash(server);
    final basic =
        base64Encode(utf8.encode('${result.username}:${result.password}'));
    // Verify the credentials by hitting /users/me — fails fast if the
    // server URL or password are wrong rather than waiting for the first
    // refresh to fail.
    final response = await _http.get<String>(
      '$normalised/api/v2/users/me',
      options: Options(
        headers: {
          'Authorization': 'Basic $basic',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode == 404) {
      // Older Komga (v1.x) only has /api/v1/users/me.
      final fallback = await _http.get<String>(
        '$normalised/api/v1/users/me',
        options: Options(
          headers: {
            'Authorization': 'Basic $basic',
            'Accept': 'application/json',
          },
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      if (fallback.statusCode != 200) {
        throw TrackerException(
          'Komga login failed (${fallback.statusCode})',
          response: fallback.data,
        );
      }
    } else if (response.statusCode != 200) {
      throw TrackerException(
        'Komga login failed (${response.statusCode})',
        response: response.data,
      );
    }
    await credentials.writeCredential(
      TrackerIds.komga,
      TrackerCredential(
        accessToken: basic,
        userdata: normalised,
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.komga);

  /// Returns (serverUrl, basicAuth) for outbound requests. Throws if the
  /// user has logged out or never logged in.
  Future<(String, String)> _ctx() async {
    final cred = await credentials.readCredential(TrackerIds.komga);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final server = cred.userdata;
    if (server == null || server.isEmpty) {
      throw TrackerException('Komga: stored credentials missing server URL');
    }
    return (server, cred.accessToken);
  }

  Future<Response<String>> _authedGet(String url, String basic) {
    return _http.get<String>(
      url,
      options: Options(
        headers: {
          'Authorization': 'Basic $basic',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    final (server, basic) = await _ctx();
    final uri = Uri.parse('$server/api/v1/series').replace(queryParameters: {
      'search': query,
      'size': '20',
    });
    final response = await _authedGet(uri.toString(), basic);
    if (response.statusCode != 200) {
      throw TrackerException(
        'Komga search failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final content = (body['content'] as List?) ?? const [];
    return content.map((raw) {
      final series = raw as Map<String, dynamic>;
      final metadata =
          (series['metadata'] as Map<String, dynamic>?) ?? const {};
      final seriesId = series['id'] as String? ?? '';
      return TrackSearchResult(
        // Komga ids are UUID strings, but Track.remoteId is int — we
        // can't store the UUID losslessly, so fall back to a stable hash
        // (and keep the canonical URL in remoteUrl for later lookup).
        remoteId: seriesId.hashCode,
        title:
            (metadata['title'] as String?)?.trim() ?? '<untitled>',
        totalChapters: (series['booksCount'] as num?)?.toInt() ?? 0,
        coverUrl: '$server/api/v1/series/$seriesId/thumbnail',
        summary: metadata['summary'] as String?,
        publishingStatus: metadata['status'] as String?,
        publishingType: null,
        startDate: metadata['publisher'] as String?,
        score: null,
        remoteUrl: '$server/api/v1/series/$seriesId',
      );
    }).toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    // Komga has no "list" you bind to — books are just on the server.
    // We still synthesise a Track so the local DB has somewhere to hang
    // the progress + tracking_url.
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.komga,
      remoteId: searchResult.remoteId,
      libraryId: null,
      title: searchResult.title,
      lastChapterRead: 0,
      totalChapters: searchResult.totalChapters,
      status: TrackStatus.planToRead,
      score: 0,
      remoteUrl: searchResult.remoteUrl,
      startDate: 0,
      finishDate: 0,
      private: false,
    );
  }

  @override
  Future<Track> refresh(Track track) async {
    final (_, basic) = await _ctx();
    final url = track.remoteUrl;
    if (url.isEmpty) {
      throw TrackerException('Komga refresh: missing tracking URL');
    }
    // tachiyomi-shaped progress endpoint lives under /api/v2/series/{id}.
    // Older v1 series URLs need to be rewritten.
    final progressUrl = url.contains('/api/v1/series/')
        ? '${url.replaceFirst('/api/v1/series/', '/api/v2/series/')}/read-progress/tachiyomi'
        : '$url/read-progress/tachiyomi';
    final response = await _authedGet(progressUrl, basic);
    if (response.statusCode != 200) {
      throw TrackerException(
        'Komga refresh failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final booksCount = (body['booksCount'] as num?)?.toInt() ?? 0;
    final booksUnread = (body['booksUnreadCount'] as num?)?.toInt() ?? 0;
    final booksRead = (body['booksReadCount'] as num?)?.toInt() ?? 0;
    final lastRead =
        (body['lastReadContinuousNumberSort'] as num?)?.toDouble() ?? 0.0;
    final maxNumber = (body['maxNumberSort'] as num?)?.toDouble() ?? 0.0;
    final komgaStatus = booksCount == booksUnread
        ? _komgaUnread
        : (booksCount == booksRead ? _komgaCompleted : _komgaReading);
    return track.copyWith(
      lastChapterRead: lastRead,
      totalChapters: maxNumber.toInt(),
      status: _statusFromKomga(komgaStatus),
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    final (_, basic) = await _ctx();
    final url = track.remoteUrl;
    if (url.isEmpty) {
      throw TrackerException('Komga update: missing tracking URL');
    }
    final progressUrl = url.contains('/api/v1/series/')
        ? '${url.replaceFirst('/api/v1/series/', '/api/v2/series/')}/read-progress/tachiyomi'
        : '$url/read-progress/tachiyomi';
    final response = await _http.put<String>(
      progressUrl,
      data: jsonEncode({'lastBookNumberSortRead': track.lastChapterRead}),
      options: Options(
        headers: {
          'Authorization': 'Basic $basic',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw TrackerException(
        'Komga update failed (${response.statusCode})',
        response: response.data,
      );
    }
    // Re-read so the canonical status reflects what the server now thinks.
    return refresh(track);
  }

  int _statusFromKomga(int komgaStatus) {
    switch (komgaStatus) {
      case _komgaCompleted:
        return TrackStatus.completed;
      case _komgaReading:
        return TrackStatus.reading;
      case _komgaUnread:
      default:
        return TrackStatus.planToRead;
    }
  }

  String _stripTrailingSlash(String url) {
    var u = url;
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  @override
  List<int> get supportedStatuses => const [
        TrackStatus.planToRead,
        TrackStatus.reading,
        TrackStatus.completed,
      ];
}
