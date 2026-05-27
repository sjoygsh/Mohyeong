import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/oauth_webview_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// MyAnimeList tracker — talks to https://api.myanimelist.net/v2.
///
/// Auth: OAuth authorization-code flow with PKCE (plain S256 challenge).
/// MAL only accepts plain PKCE — i.e. `code_challenge` == `code_verifier`.
class MyAnimeListTracker extends Tracker {
  MyAnimeListTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(TrackerIds.myAnimeList, 'MyAnimeList', TrackerCategory.online);

  // Patched at build time; placeholder for the public repo.
  static const String _clientId = '0';
  static const String _redirectUri = 'mohyeong://mal-auth';
  static const String _apiUrl = 'https://api.myanimelist.net/v2';
  static const String _authUrl = 'https://myanimelist.net/v1/oauth2';
  static const String _baseUrl = 'https://myanimelist.net';

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  bool get supportsPrivateTracking => false;

  @override
  Future<bool> get isLoggedIn =>
      credentials.isAuthenticated(TrackerIds.myAnimeList);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('MyAnimeListTracker.dio not attached');
    return d;
  }

  String _generateVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    // MAL uses 'plain' PKCE so verifier == challenge. Length 128 keeps us
    // inside the RFC 7636 max while staying compatible with MAL's parser.
    return List.generate(128, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  Future<void> login() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      throw StateError('No navigator available to drive the OAuth flow.');
    }
    final verifier = _generateVerifier();
    final authUrl = Uri.parse('$_authUrl/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'code_challenge': verifier,
        'code_challenge_method': 'plain',
      },
    );
    final navigator = Navigator.of(ctx);
    final code = await navigator.push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => OAuthWebViewScreen(
          title: 'Log in to MyAnimeList',
          authorizationUrl: authUrl.toString(),
          redirectScheme: _redirectUri,
        ),
      ),
    );
    if (code == null || code.isEmpty) {
      throw TrackerException('MyAnimeList login cancelled');
    }
    final tokenResponse = await _http.post<String>(
      '$_authUrl/token',
      data: {
        'client_id': _clientId,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': _redirectUri,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (tokenResponse.statusCode != 200) {
      throw TrackerException(
        'MAL token exchange failed: ${tokenResponse.statusCode}',
        response: tokenResponse.data,
      );
    }
    final tok = jsonDecode(tokenResponse.data ?? '{}') as Map<String, dynamic>;
    await credentials.writeCredential(
      TrackerIds.myAnimeList,
      TrackerCredential(
        accessToken: tok['access_token'] as String,
        refreshToken: tok['refresh_token'] as String?,
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.myAnimeList);

  Future<Response<String>> _authedGet(String path,
      [Map<String, dynamic>? query]) async {
    final cred = await credentials.readCredential(TrackerIds.myAnimeList);
    if (cred == null) throw TrackerNotAuthenticated(name);
    return _http.get<String>(
      '$_apiUrl$path',
      queryParameters: query,
      options: Options(
        headers: {'Authorization': 'Bearer ${cred.accessToken}'},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  Future<Response<String>> _authedPut(
    String path,
    Map<String, dynamic> form,
  ) async {
    final cred = await credentials.readCredential(TrackerIds.myAnimeList);
    if (cred == null) throw TrackerNotAuthenticated(name);
    return _http.put<String>(
      '$_apiUrl$path',
      data: form,
      options: Options(
        headers: {'Authorization': 'Bearer ${cred.accessToken}'},
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    final response = await _authedGet('/manga', {
      'q': query,
      'limit': 20,
      'fields':
          'id,title,num_chapters,main_picture,synopsis,status,media_type,start_date,mean',
    });
    if (response.statusCode != 200) {
      throw TrackerException(
        'MAL search failed: ${response.statusCode}',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final data = body['data'] as List? ?? const [];
    return data.map((entry) {
      final node = (entry as Map<String, dynamic>)['node'] as Map<String, dynamic>;
      final pic = node['main_picture'] as Map<String, dynamic>?;
      final id = node['id'] as int;
      return TrackSearchResult(
        remoteId: id,
        title: node['title'] as String? ?? '<untitled>',
        totalChapters: (node['num_chapters'] as int?) ?? 0,
        coverUrl: pic?['large'] as String? ?? pic?['medium'] as String?,
        summary: node['synopsis'] as String?,
        publishingStatus: node['status'] as String?,
        publishingType: node['media_type'] as String?,
        startDate: node['start_date'] as String?,
        score: (node['mean'] as num?)?.toDouble(),
        remoteUrl: '$_baseUrl/manga/$id',
      );
    }).toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    await _authedPut(
      '/manga/${searchResult.remoteId}/my_list_status',
      {'status': 'plan_to_read'},
    );
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.myAnimeList,
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
    final response = await _authedGet('/manga/${track.remoteId}', {
      'fields':
          'id,title,num_chapters,my_list_status{status,score,num_chapters_read,start_date,finish_date}',
    });
    if (response.statusCode != 200) {
      throw TrackerException(
        'MAL refresh failed: ${response.statusCode}',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final myStatus = body['my_list_status'] as Map<String, dynamic>?;
    return track.copyWith(
      title: body['title'] as String? ?? track.title,
      totalChapters:
          (body['num_chapters'] as int?) ?? track.totalChapters,
      lastChapterRead:
          ((myStatus?['num_chapters_read'] as num?) ?? track.lastChapterRead)
              .toDouble(),
      status: _statusFromMal(myStatus?['status'] as String?),
      score: ((myStatus?['score'] as num?) ?? track.score).toDouble(),
      startDate: _dateFromMal(myStatus?['start_date']),
      finishDate: _dateFromMal(myStatus?['finish_date']),
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    await _authedPut('/manga/${track.remoteId}/my_list_status', {
      'status': _statusToMal(track.status),
      'num_chapters_read': track.lastChapterRead.toInt(),
      'score': track.score.toInt(),
    });
    return track;
  }

  String _statusToMal(int status) {
    switch (status) {
      case TrackStatus.reading:
        return 'reading';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
      case TrackStatus.rereading:
        return 'reading';
      case TrackStatus.planToRead:
      default:
        return 'plan_to_read';
    }
  }

  int _statusFromMal(String? s) {
    switch (s) {
      case 'reading':
        return TrackStatus.reading;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      case 'plan_to_read':
        return TrackStatus.planToRead;
      default:
        return TrackStatus.planToRead;
    }
  }

  int _dateFromMal(Object? raw) {
    if (raw is! String || raw.isEmpty) return 0;
    final parsed = DateTime.tryParse(raw);
    return parsed?.millisecondsSinceEpoch ?? 0;
  }
}
