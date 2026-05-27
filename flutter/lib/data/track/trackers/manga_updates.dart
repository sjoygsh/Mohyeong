import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/credentials_login_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// MangaUpdates tracker — talks to https://api.mangaupdates.com.
///
/// Auth: username/password against `PUT /v1/account/login`, which returns
/// a long-lived bearer token. The token is stored in the
/// [TrackCredentialStore] as the access token; the numeric `uid` lands in
/// the userdata field so we have something to differentiate accounts in
/// the future.
///
/// MangaUpdates uses its own list ids that don't match Mihon's canonical
/// [TrackStatus] codes byte-for-byte. We translate both ways at the API
/// boundary so the DB-level status stays in canonical Mihon form.
class MangaUpdatesTracker extends Tracker {
  MangaUpdatesTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(
          TrackerIds.mangaUpdates,
          'MangaUpdates',
          TrackerCategory.online,
        );

  static const String _apiUrl = 'https://api.mangaupdates.com';
  static const String _baseUrl = 'https://www.mangaupdates.com';

  // MangaUpdates list ids — mirror Mihon's `MangaUpdates.kt` constants.
  static const int _readingList = 0;
  static const int _wishList = 1;
  static const int _completeList = 2;
  static const int _unfinishedList = 3;
  static const int _onHoldList = 4;

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  Future<bool> get isLoggedIn =>
      credentials.isAuthenticated(TrackerIds.mangaUpdates);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('MangaUpdatesTracker.dio not attached');
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
          title: 'Log in to MangaUpdates',
          helperText:
              'Enter the username and password you use on mangaupdates.com.',
        ),
      ),
    );
    if (result == null) {
      throw TrackerException('MangaUpdates login cancelled');
    }
    if (result.username.isEmpty || result.password.isEmpty) {
      throw TrackerException(
        'MangaUpdates login: username and password are required',
      );
    }
    final response = await _http.put<String>(
      '$_apiUrl/v1/account/login',
      data: jsonEncode({
        'username': result.username,
        'password': result.password,
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'MangaUpdates login failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final context = body['context'] as Map<String, dynamic>?;
    final token = context?['session_token'] as String?;
    final uid = context?['uid'];
    if (token == null || token.isEmpty) {
      throw TrackerException(
        'MangaUpdates login: response missing session token',
        response: response.data,
      );
    }
    await credentials.writeCredential(
      TrackerIds.mangaUpdates,
      TrackerCredential(
        accessToken: token,
        userdata: uid == null ? null : '$uid',
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.mangaUpdates);

  Future<Response<String>> _authed(
    String method,
    String path, {
    Object? data,
  }) async {
    final cred = await credentials.readCredential(TrackerIds.mangaUpdates);
    if (cred == null) throw TrackerNotAuthenticated(name);
    return _http.request<String>(
      '$_apiUrl$path',
      data: data == null ? null : jsonEncode(data),
      options: Options(
        method: method,
        headers: {
          'Authorization': 'Bearer ${cred.accessToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    // Search does not require auth on MangaUpdates' API.
    final response = await _http.post<String>(
      '$_apiUrl/v1/series/search',
      data: jsonEncode({
        'search': query,
        // Mihon filters out drama-cd + novel — keep parity so the result
        // list looks the same as the Kotlin app.
        'filter_types': ['drama cd', 'novel'],
      }),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'MangaUpdates search failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    return results
        .map((raw) {
          final result = raw as Map<String, dynamic>;
          final record =
              (result['record'] as Map<String, dynamic>?) ?? const {};
          final seriesId =
              (record['series_id'] as num?)?.toInt() ?? 0;
          final image = record['image'] as Map<String, dynamic>?;
          final imageUrl = image?['url'] as Map<String, dynamic>?;
          return TrackSearchResult(
            remoteId: seriesId,
            title: (record['title'] as String?)?.trim() ?? '<untitled>',
            totalChapters: (record['latest_chapter'] as num?)?.toInt() ?? 0,
            coverUrl: imageUrl?['original'] as String?,
            summary: record['description'] as String?,
            publishingStatus: null,
            publishingType: record['type'] as String?,
            startDate: record['year']?.toString(),
            score: (record['bayesian_rating'] as num?)?.toDouble(),
            remoteUrl:
                (record['url'] as String?) ?? '$_baseUrl/series/$seriesId',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    final response = await _authed(
      'POST',
      '/v1/lists/series',
      data: [
        {
          'series': {'id': searchResult.remoteId},
          'list_id': _wishList,
        },
      ],
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'MangaUpdates bind failed (${response.statusCode})',
        response: response.data,
      );
    }
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.mangaUpdates,
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
    final listItemResp =
        await _authed('GET', '/v1/lists/series/${track.remoteId}');
    if (listItemResp.statusCode != 200) {
      throw TrackerException(
        'MangaUpdates refresh failed (${listItemResp.statusCode})',
        response: listItemResp.data,
      );
    }
    final listBody =
        jsonDecode(listItemResp.data ?? '{}') as Map<String, dynamic>;
    final remoteListId = (listBody['list_id'] as num?)?.toInt() ?? _wishList;
    final status =
        (listBody['status'] as Map<String, dynamic>?) ?? const {};
    final chapter = (status['chapter'] as num?)?.toDouble() ?? 0.0;

    // Score lives in a separate endpoint and may legitimately 404 when the
    // user hasn't rated the series. We collapse that into score=0.
    double score = 0;
    final ratingResp =
        await _authed('GET', '/v1/series/${track.remoteId}/rating');
    if (ratingResp.statusCode == 200) {
      final ratingBody =
          jsonDecode(ratingResp.data ?? '{}') as Map<String, dynamic>;
      score = (ratingBody['rating'] as num?)?.toDouble() ?? 0.0;
    }
    return track.copyWith(
      lastChapterRead: chapter,
      status: _statusFromMangaUpdates(remoteListId),
      score: score,
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    var nextStatus = track.status;
    // Mihon parity: starting to read auto-flips from any non-completed list
    // to "reading".
    if (nextStatus != TrackStatus.completed && didReadChapter) {
      nextStatus = TrackStatus.reading;
    }
    final remoteListId = _statusToMangaUpdates(nextStatus);
    final updateResp = await _authed(
      'POST',
      '/v1/lists/series/update',
      data: [
        {
          'series': {'id': track.remoteId},
          'list_id': remoteListId,
          'status': {'chapter': track.lastChapterRead.toInt()},
        },
      ],
    );
    if (updateResp.statusCode != 200) {
      throw TrackerException(
        'MangaUpdates update failed (${updateResp.statusCode})',
        response: updateResp.data,
      );
    }
    if (track.score > 0) {
      final ratingResp = await _authed(
        'PUT',
        '/v1/series/${track.remoteId}/rating',
        data: {'rating': track.score},
      );
      if (ratingResp.statusCode != 200) {
        throw TrackerException(
          'MangaUpdates score update failed (${ratingResp.statusCode})',
          response: ratingResp.data,
        );
      }
    } else {
      // Score zeroed → delete the rating to match Mihon's behaviour.
      await _authed('DELETE', '/v1/series/${track.remoteId}/rating');
    }
    return track.copyWith(status: nextStatus);
  }

  int _statusToMangaUpdates(int canonical) {
    switch (canonical) {
      case TrackStatus.reading:
      case TrackStatus.rereading:
        return _readingList;
      case TrackStatus.completed:
        return _completeList;
      case TrackStatus.onHold:
        return _onHoldList;
      case TrackStatus.dropped:
        return _unfinishedList;
      case TrackStatus.planToRead:
      default:
        return _wishList;
    }
  }

  int _statusFromMangaUpdates(int remoteListId) {
    switch (remoteListId) {
      case _readingList:
        return TrackStatus.reading;
      case _completeList:
        return TrackStatus.completed;
      case _onHoldList:
        return TrackStatus.onHold;
      case _unfinishedList:
        return TrackStatus.dropped;
      case _wishList:
      default:
        return TrackStatus.planToRead;
    }
  }

  @override
  List<int> get supportedStatuses => const [
        TrackStatus.reading,
        TrackStatus.completed,
        TrackStatus.onHold,
        TrackStatus.dropped,
        TrackStatus.planToRead,
      ];
}
