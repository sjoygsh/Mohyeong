import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/oauth_webview_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// Shikimori tracker — talks to https://shikimori.one.
///
/// Auth: OAuth2 authorization-code grant. The webview lands on
/// `mohyeong://shikimori-auth?code=...`; we then exchange the code for an
/// access + refresh token. Shikimori requires a stable, identifiable
/// User-Agent on every request — they will rate-limit / block generic
/// agents.
class ShikimoriTracker extends Tracker {
  ShikimoriTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(TrackerIds.shikimori, 'Shikimori', TrackerCategory.online);

  // The registered Shikimori OAuth application for this build. Empty in the
  // public repo: these identify whoever ships the app, so they cannot live in
  // source. Supply them at build time —
  //   --dart-define=SHIKIMORI_CLIENT_ID=... --dart-define=SHIKIMORI_CLIENT_SECRET=...
  // Without them [isConfigured] is false and the UI says sign-in is
  // unavailable, rather than opening a page Shikimori will reject.
  static const String _clientId =
      String.fromEnvironment('SHIKIMORI_CLIENT_ID');
  static const String _clientSecret =
      String.fromEnvironment('SHIKIMORI_CLIENT_SECRET');
  static const String _redirectUri = 'mohyeong://shikimori-auth';
  static const String _baseUrl = 'https://shikimori.one';
  static const String _apiUrl = '$_baseUrl/api';
  static const String _oauthUrl = '$_baseUrl/oauth';
  static const String _userAgent = 'Mohyeong';

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  Future<bool> get isLoggedIn =>
      credentials.isAuthenticated(TrackerIds.shikimori);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('ShikimoriTracker.dio not attached');
    return d;
  }

  @override
  bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  @override
  Future<void> login() async {
    if (!isConfigured) {
      throw TrackerException(
          'Shikimori sign-in isn\'t available in this build.');
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      throw StateError('No navigator available to drive the OAuth flow.');
    }
    final authUrl = Uri.parse('$_oauthUrl/authorize').replace(
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'scope': 'user_rates',
      },
    );
    final code = await Navigator.of(ctx).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => OAuthWebViewScreen(
          title: 'Log in to Shikimori',
          authorizationUrl: authUrl.toString(),
          redirectScheme: _redirectUri,
        ),
      ),
    );
    if (code == null || code.isEmpty) {
      throw TrackerException('Shikimori login cancelled');
    }
    final tokenResp = await _http.post<String>(
      '$_oauthUrl/token',
      data: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'redirect_uri': _redirectUri,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        headers: {'User-Agent': _userAgent},
        validateStatus: (_) => true,
      ),
    );
    if (tokenResp.statusCode != 200) {
      throw TrackerException(
        'Shikimori token exchange failed (${tokenResp.statusCode})',
        response: tokenResp.data,
      );
    }
    final tok = jsonDecode(tokenResp.data ?? '{}') as Map<String, dynamic>;
    final access = tok['access_token'] as String?;
    final refresh = tok['refresh_token'] as String?;
    if (access == null || access.isEmpty) {
      throw TrackerException('Shikimori login: missing access token');
    }
    // Look up the user id so future /user_rates calls can scope by it.
    final whoamiResp = await _http.get<String>(
      '$_apiUrl/users/whoami',
      options: Options(
        headers: {
          'Authorization': 'Bearer $access',
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    String? userId;
    if (whoamiResp.statusCode == 200) {
      final body =
          jsonDecode(whoamiResp.data ?? '{}') as Map<String, dynamic>;
      final id = body['id'];
      if (id != null) userId = '$id';
    }
    await credentials.writeCredential(
      TrackerIds.shikimori,
      TrackerCredential(
        accessToken: access,
        refreshToken: refresh,
        userdata: userId,
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.shikimori);

  Future<Response<String>> _authed(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    final cred = await credentials.readCredential(TrackerIds.shikimori);
    if (cred == null) throw TrackerNotAuthenticated(name);
    return _http.request<String>(
      '$_apiUrl$path',
      data: data == null ? null : jsonEncode(data),
      queryParameters: query,
      options: Options(
        method: method,
        headers: {
          'Authorization': 'Bearer ${cred.accessToken}',
          'User-Agent': _userAgent,
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
    final response = await _http.get<String>(
      '$_apiUrl/mangas',
      queryParameters: {'search': query, 'limit': 20},
      options: Options(
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Shikimori search failed (${response.statusCode})',
        response: response.data,
      );
    }
    final list = jsonDecode(response.data ?? '[]') as List;
    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = (m['id'] as num?)?.toInt() ?? 0;
      final cover = m['image'] as Map<String, dynamic>?;
      final originalCover = cover?['original'] as String?;
      final coverUrl = originalCover != null
          ? (originalCover.startsWith('http')
              ? originalCover
              : '$_baseUrl$originalCover')
          : null;
      return TrackSearchResult(
        remoteId: id,
        title: (m['russian'] as String?)?.isNotEmpty == true
            ? m['russian'] as String
            : (m['name'] as String?) ?? '<untitled>',
        totalChapters: (m['chapters'] as int?) ?? 0,
        coverUrl: coverUrl,
        summary: null,
        publishingStatus: m['status'] as String?,
        publishingType: m['kind'] as String?,
        startDate: m['aired_on'] as String?,
        score: (m['score'] is String)
            ? double.tryParse(m['score'] as String)
            : (m['score'] as num?)?.toDouble(),
        remoteUrl:
            '$_baseUrl${m['url'] ?? '/mangas/$id'}',
      );
    }).toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    final cred = await credentials.readCredential(TrackerIds.shikimori);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final userId = cred.userdata;
    if (userId == null || userId.isEmpty) {
      throw TrackerException(
        'Shikimori bind: missing user id (log out and back in).',
      );
    }
    final response = await _authed(
      'POST',
      '/v2/user_rates',
      data: {
        'user_rate': {
          'user_id': int.tryParse(userId) ?? userId,
          'target_id': searchResult.remoteId,
          'target_type': 'Manga',
          'status': 'planned',
        },
      },
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw TrackerException(
        'Shikimori bind failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final libraryId = (body['id'] as num?)?.toInt();
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.shikimori,
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
    final cred = await credentials.readCredential(TrackerIds.shikimori);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final userId = cred.userdata;
    if (userId == null || userId.isEmpty) {
      throw TrackerException(
        'Shikimori refresh: missing user id (log out and back in).',
      );
    }
    final response = await _authed(
      'GET',
      '/v2/user_rates',
      query: {
        'user_id': userId,
        'target_id': track.remoteId.toString(),
        'target_type': 'Manga',
      },
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Shikimori refresh failed (${response.statusCode})',
        response: response.data,
      );
    }
    final entries = jsonDecode(response.data ?? '[]') as List;
    if (entries.isEmpty) return track;
    final e = entries.first as Map<String, dynamic>;
    return track.copyWith(
      libraryId: (e['id'] as num?)?.toInt() ?? track.libraryId,
      lastChapterRead:
          ((e['chapters'] as num?) ?? track.lastChapterRead).toDouble(),
      status: _statusFromShikimori(e['status'] as String?),
      // Shikimori scores are 0..10 in whole numbers — matches Mihon.
      score: ((e['score'] as num?) ?? 0).toDouble(),
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    final libraryId = track.libraryId;
    if (libraryId == null) {
      throw TrackerException(
        'Shikimori update: track is not bound (libraryId is null).',
      );
    }
    var nextStatus = track.status;
    if (nextStatus != TrackStatus.completed && didReadChapter) {
      nextStatus = TrackStatus.reading;
    }
    final response = await _authed(
      'PATCH',
      '/v2/user_rates/$libraryId',
      data: {
        'user_rate': {
          'status': _statusToShikimori(nextStatus),
          'chapters': track.lastChapterRead.toInt(),
          'score': track.score.toInt(),
        },
      },
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Shikimori update failed (${response.statusCode})',
        response: response.data,
      );
    }
    return track.copyWith(status: nextStatus);
  }

  String _statusToShikimori(int status) {
    switch (status) {
      case TrackStatus.reading:
        return 'watching';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
      case TrackStatus.rereading:
        return 'rewatching';
      case TrackStatus.planToRead:
      default:
        return 'planned';
    }
  }

  int _statusFromShikimori(String? s) {
    switch (s) {
      case 'watching':
        return TrackStatus.reading;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      case 'rewatching':
        return TrackStatus.rereading;
      case 'planned':
        return TrackStatus.planToRead;
      default:
        return TrackStatus.planToRead;
    }
  }
}
