import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/credentials_login_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// Kitsu tracker — talks to https://kitsu.io/api/edge (JSON:API style).
///
/// Auth: OAuth2 Resource Owner Password Credentials grant against
/// `https://kitsu.io/api/oauth/token`. The user enters their kitsu.io
/// username/password directly; we exchange them for an access + refresh
/// token. The numeric user id (needed to scope library lookups) is fetched
/// once via `GET /users?filter[self]=true` and stashed in
/// [TrackerCredential.userdata].
///
/// Status mapping mirrors Mihon's Kitsu adapter: their list strings are
/// `current` / `planned` / `completed` / `on_hold` / `dropped`. There is
/// no "rereading" list — it collapses to `current` on the wire.
class KitsuTracker extends Tracker {
  KitsuTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(TrackerIds.kitsu, 'Kitsu', TrackerCategory.online);

  static const String _apiUrl = 'https://kitsu.io/api/edge';
  static const String _baseUrl = 'https://kitsu.io';
  static const String _tokenUrl = 'https://kitsu.io/api/oauth/token';
  // Kitsu publishes a permanent oauth client id+secret for native clients;
  // these are the same values Mihon ships. They aren't user-bound secrets.
  static const String _clientId =
      'dd031b32d2f56c990b1425efe6c42ad847e7fe3ab46bf1299f05ecd856bdb7dd';
  static const String _clientSecret =
      '54d7307928f63414defd96399fc31ba847961ceaecef3a5fd93144e960c0e151';

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  Future<bool> get isLoggedIn => credentials.isAuthenticated(TrackerIds.kitsu);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('KitsuTracker.dio not attached');
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
          title: 'Log in to Kitsu',
          usernameLabel: 'Email or username',
          helperText:
              'Enter the email/username and password you use on kitsu.io.',
        ),
      ),
    );
    if (result == null) {
      throw TrackerException('Kitsu login cancelled');
    }
    if (result.username.isEmpty || result.password.isEmpty) {
      throw TrackerException(
        'Kitsu login: username and password are required',
      );
    }
    final tokenResp = await _http.post<String>(
      _tokenUrl,
      data: {
        'grant_type': 'password',
        'username': result.username,
        'password': result.password,
        'client_id': _clientId,
        'client_secret': _clientSecret,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (tokenResp.statusCode != 200) {
      throw TrackerException(
        'Kitsu login failed (${tokenResp.statusCode})',
        response: tokenResp.data,
      );
    }
    final tok = jsonDecode(tokenResp.data ?? '{}') as Map<String, dynamic>;
    final access = tok['access_token'] as String?;
    final refresh = tok['refresh_token'] as String?;
    if (access == null || access.isEmpty) {
      throw TrackerException('Kitsu login: response missing access token');
    }
    // Look up the numeric user id with the freshly-minted token so we can
    // scope future /library-entries calls.
    final userResp = await _http.get<String>(
      '$_apiUrl/users',
      queryParameters: {'filter[self]': 'true'},
      options: Options(
        headers: {
          'Authorization': 'Bearer $access',
          'Accept': 'application/vnd.api+json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    String? userId;
    if (userResp.statusCode == 200) {
      final body =
          jsonDecode(userResp.data ?? '{}') as Map<String, dynamic>;
      final data = body['data'];
      if (data is List && data.isNotEmpty) {
        userId = (data.first as Map<String, dynamic>)['id'] as String?;
      }
    }
    await credentials.writeCredential(
      TrackerIds.kitsu,
      TrackerCredential(
        accessToken: access,
        refreshToken: refresh,
        userdata: userId,
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.kitsu);

  Future<Response<String>> _authed(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    final cred = await credentials.readCredential(TrackerIds.kitsu);
    if (cred == null) throw TrackerNotAuthenticated(name);
    return _http.request<String>(
      '$_apiUrl$path',
      data: data == null ? null : jsonEncode(data),
      queryParameters: query,
      options: Options(
        method: method,
        headers: {
          'Authorization': 'Bearer ${cred.accessToken}',
          'Content-Type': 'application/vnd.api+json',
          'Accept': 'application/vnd.api+json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    // Search does not require auth.
    final response = await _http.get<String>(
      '$_apiUrl/manga',
      queryParameters: {
        'filter[text]': query,
        'page[limit]': '20',
      },
      options: Options(
        headers: {'Accept': 'application/vnd.api+json'},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Kitsu search failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final results = (body['data'] as List?) ?? const [];
    return results.map((raw) {
      final entry = raw as Map<String, dynamic>;
      final id = int.tryParse(entry['id'] as String? ?? '0') ?? 0;
      final attrs =
          (entry['attributes'] as Map<String, dynamic>?) ?? const {};
      final titles = attrs['titles'] as Map<String, dynamic>?;
      final poster = attrs['posterImage'] as Map<String, dynamic>?;
      final canonical = (attrs['canonicalTitle'] as String?) ??
          (titles?['en_jp'] as String?) ??
          (titles?['en'] as String?) ??
          '<untitled>';
      final score = attrs['averageRating'];
      double? parsedScore;
      if (score is num) {
        parsedScore = score.toDouble();
      } else if (score is String) {
        parsedScore = double.tryParse(score);
      }
      return TrackSearchResult(
        remoteId: id,
        title: canonical,
        totalChapters: (attrs['chapterCount'] as int?) ?? 0,
        coverUrl: (poster?['large'] as String?) ??
            (poster?['medium'] as String?) ??
            (poster?['small'] as String?),
        summary: attrs['synopsis'] as String?,
        publishingStatus: attrs['status'] as String?,
        publishingType: attrs['mangaType'] as String?,
        startDate: attrs['startDate'] as String?,
        score: parsedScore,
        remoteUrl: '$_baseUrl/manga/${attrs['slug'] ?? id}',
      );
    }).toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    final cred = await credentials.readCredential(TrackerIds.kitsu);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final userId = cred.userdata;
    if (userId == null || userId.isEmpty) {
      throw TrackerException(
        'Kitsu bind: missing user id (try logging out and back in).',
      );
    }
    final response = await _authed(
      'POST',
      '/library-entries',
      data: {
        'data': {
          'type': 'libraryEntries',
          'attributes': {
            'status': 'planned',
            'progress': 0,
          },
          'relationships': {
            'user': {
              'data': {'type': 'users', 'id': userId},
            },
            'media': {
              'data': {
                'type': 'manga',
                'id': searchResult.remoteId.toString(),
              },
            },
          },
        },
      },
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw TrackerException(
        'Kitsu bind failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    final libraryId = data == null
        ? null
        : int.tryParse(data['id'] as String? ?? '');
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.kitsu,
      remoteId: searchResult.remoteId,
      libraryId: libraryId,
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
    final cred = await credentials.readCredential(TrackerIds.kitsu);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final userId = cred.userdata;
    if (userId == null || userId.isEmpty) {
      throw TrackerException(
        'Kitsu refresh: missing user id (try logging out and back in).',
      );
    }
    final response = await _authed(
      'GET',
      '/library-entries',
      query: {
        'filter[user_id]': userId,
        'filter[manga_id]': track.remoteId.toString(),
        'include': 'manga',
        'fields[manga]': 'canonicalTitle,chapterCount,slug',
      },
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Kitsu refresh failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final entries = (body['data'] as List?) ?? const [];
    if (entries.isEmpty) {
      // Entry was deleted on Kitsu out from under us — leave the local
      // record alone rather than wipe it.
      return track;
    }
    final entry = entries.first as Map<String, dynamic>;
    final attrs =
        (entry['attributes'] as Map<String, dynamic>?) ?? const {};
    final libraryId = int.tryParse(entry['id'] as String? ?? '');
    // The manga record lives in `included[]`; pull total chapters from it
    // if it's present, otherwise keep the cached value.
    int totalChapters = track.totalChapters;
    String title = track.title;
    final included = body['included'] as List? ?? const [];
    for (final inc in included) {
      final m = inc as Map<String, dynamic>;
      if (m['type'] == 'manga') {
        final mAttrs =
            (m['attributes'] as Map<String, dynamic>?) ?? const {};
        totalChapters = (mAttrs['chapterCount'] as int?) ?? totalChapters;
        title = (mAttrs['canonicalTitle'] as String?) ?? title;
        break;
      }
    }
    return track.copyWith(
      libraryId: libraryId ?? track.libraryId,
      title: title,
      totalChapters: totalChapters,
      lastChapterRead:
          ((attrs['progress'] as num?) ?? track.lastChapterRead).toDouble(),
      status: _statusFromKitsu(attrs['status'] as String?),
      // Kitsu scores are 2..20 (representing 1..10 in half-star increments).
      // Mihon stores 0..10, so divide by 2.
      score: ((attrs['ratingTwenty'] as num?) ?? 0).toDouble() / 2,
      startDate: _dateFromKitsu(attrs['startedAt']),
      finishDate: _dateFromKitsu(attrs['finishedAt']),
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    final libraryId = track.libraryId;
    if (libraryId == null) {
      throw TrackerException(
        'Kitsu update: track is not bound (libraryId is null).',
      );
    }
    var nextStatus = track.status;
    if (nextStatus != TrackStatus.completed && didReadChapter) {
      nextStatus = TrackStatus.reading;
    }
    final response = await _authed(
      'PATCH',
      '/library-entries/$libraryId',
      data: {
        'data': {
          'type': 'libraryEntries',
          'id': libraryId.toString(),
          'attributes': {
            'status': _statusToKitsu(nextStatus),
            'progress': track.lastChapterRead.toInt(),
            // Mihon 0..10 → Kitsu ratingTwenty 0..20.
            'ratingTwenty': (track.score * 2).round(),
          },
        },
      },
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Kitsu update failed (${response.statusCode})',
        response: response.data,
      );
    }
    return track.copyWith(status: nextStatus);
  }

  String _statusToKitsu(int status) {
    switch (status) {
      case TrackStatus.reading:
        return 'current';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
      case TrackStatus.rereading:
        // Kitsu has no "rereading" list — fold to "current" but preserve
        // the canonical status locally so the UI still labels it correctly.
        return 'current';
      case TrackStatus.planToRead:
      default:
        return 'planned';
    }
  }

  int _statusFromKitsu(String? s) {
    switch (s) {
      case 'current':
        return TrackStatus.reading;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      case 'planned':
        return TrackStatus.planToRead;
      default:
        return TrackStatus.planToRead;
    }
  }

  int _dateFromKitsu(Object? raw) {
    if (raw is! String || raw.isEmpty) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
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
