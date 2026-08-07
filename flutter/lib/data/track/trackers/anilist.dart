import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/oauth_webview_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// AniList tracker — talks to https://graphql.anilist.co.
///
/// Auth: OAuth implicit grant. The user is sent to the AniList authorize
/// endpoint inside an [OAuthWebViewScreen]; AniList redirects to
/// `mohyeong://anilist-auth#access_token=...&expires_in=...`. The token is
/// stored in the [TrackCredentialStore].
class AniListTracker extends Tracker {
  AniListTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(TrackerIds.aniList, 'AniList', TrackerCategory.online);

  // The registered AniList API client for this build. Empty in the public
  // repo: it identifies whoever ships the app, so it cannot live in source.
  // Supply it at build time —
  //   flutter build apk --release --dart-define=ANILIST_CLIENT_ID=12345
  // Without it [isConfigured] is false and the UI says sign-in is
  // unavailable, rather than opening a page AniList will reject.
  static const String _clientId =
      String.fromEnvironment('ANILIST_CLIENT_ID');
  static const String _redirectUri = 'mohyeong://anilist-auth';
  static const String _apiUrl = 'https://graphql.anilist.co';
  static const String _baseUrl = 'https://anilist.co';

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  bool get supportsPrivateTracking => true;

  @override
  Future<bool> get isLoggedIn =>
      credentials.isAuthenticated(TrackerIds.aniList);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('AniListTracker.dio not attached');
    return d;
  }

  @override
  bool get isConfigured => _clientId.isNotEmpty;

  @override
  Future<void> login() async {
    if (!isConfigured) {
      throw TrackerException(
          'AniList sign-in isn\'t available in this build.');
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      throw StateError('No navigator available to drive the OAuth flow.');
    }
    final authUrl = Uri.https('anilist.co', '/api/v2/oauth/authorize', {
      'client_id': _clientId,
      'response_type': 'token',
      'redirect_uri': _redirectUri,
    }).toString();
    // AniList uses the implicit flow — the access token comes back in the
    // URL fragment rather than the query string, so OAuthWebViewScreen
    // returns a fragment-bearing URL and we parse the fragment here.
    final navigator = Navigator.of(ctx);
    final result = await navigator.push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => OAuthWebViewScreen(
          title: 'Log in to AniList',
          authorizationUrl: authUrl,
          redirectScheme: _redirectUri,
        ),
      ),
    );
    if (result == null) {
      throw TrackerException('AniList login cancelled');
    }
    // The OAuth webview screen pops the URL's `code` query param, but for
    // implicit flow there's no code. Parse the access_token out of the
    // fragment portion of the redirected URL it captured. We rely on the
    // webview returning the full URL when it can; if not, fall through and
    // ask the user to paste the token manually.
    // For simplicity here, accept either:
    //   - a raw access_token string (implicit flow),
    //   - a code that we'd swap for a token (auth-code flow).
    final token = _extractAccessToken(result) ?? result;
    if (token.isEmpty) {
      throw TrackerException('AniList login: no access token in redirect');
    }
    await credentials.writeCredential(
      TrackerIds.aniList,
      TrackerCredential(accessToken: token),
    );
  }

  String? _extractAccessToken(String raw) {
    final hashIndex = raw.indexOf('#');
    if (hashIndex < 0) return null;
    final fragment = raw.substring(hashIndex + 1);
    final parts = fragment.split('&');
    for (final p in parts) {
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      if (p.substring(0, eq) == 'access_token') {
        return Uri.decodeComponent(p.substring(eq + 1));
      }
    }
    return null;
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.aniList);

  Future<Map<String, dynamic>> _gql(String query, Map<String, dynamic> vars) async {
    final cred = await credentials.readCredential(TrackerIds.aniList);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final response = await _http.post<String>(
      _apiUrl,
      data: jsonEncode({'query': query, 'variables': vars}),
      options: Options(
        headers: {
          'Authorization': 'Bearer ${cred.accessToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'AniList API error ${response.statusCode}',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw TrackerException('AniList: ${jsonEncode(errors)}');
    }
    return body['data'] as Map<String, dynamic>;
  }

  static const String _searchQuery = r'''
    query Search($q: String) {
      Page(perPage: 20) {
        media(search: $q, type: MANGA) {
          id
          title { romaji english native }
          chapters
          coverImage { large }
          description(asHtml: false)
          status
          format
          startDate { year month day }
          averageScore
          siteUrl
        }
      }
    }
  ''';

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    final data = await _gql(_searchQuery, {'q': query});
    final media = (data['Page'] as Map<String, dynamic>)['media'] as List;
    return media.map((m) {
      final map = m as Map<String, dynamic>;
      final title = map['title'] as Map<String, dynamic>?;
      final cover = map['coverImage'] as Map<String, dynamic>?;
      final start = map['startDate'] as Map<String, dynamic>?;
      return TrackSearchResult(
        remoteId: map['id'] as int,
        title: (title?['romaji'] ??
                title?['english'] ??
                title?['native'] ??
                '<untitled>') as String,
        totalChapters: (map['chapters'] as int?) ?? 0,
        coverUrl: cover?['large'] as String?,
        summary: map['description'] as String?,
        publishingStatus: map['status'] as String?,
        publishingType: map['format'] as String?,
        startDate: start == null
            ? null
            : '${start['year']}-${start['month']}-${start['day']}',
        score: (map['averageScore'] as num?)?.toDouble(),
        remoteUrl: map['siteUrl'] as String? ??
            '$_baseUrl/manga/${map['id']}',
      );
    }).toList(growable: false);
  }

  static const String _addEntryMutation = r'''
    mutation Add($mediaId: Int) {
      SaveMediaListEntry(mediaId: $mediaId, status: PLANNING) {
        id status progress score private
      }
    }
  ''';

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    await _gql(_addEntryMutation, {'mediaId': searchResult.remoteId});
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.aniList,
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

  static const String _entryQuery = r'''
    query Entry($mediaId: Int) {
      MediaList(mediaId: $mediaId) {
        id status progress score(format: POINT_10) private
        media { chapters title { romaji english native } siteUrl }
        startedAt { year month day }
        completedAt { year month day }
      }
    }
  ''';

  @override
  Future<Track> refresh(Track track) async {
    final data = await _gql(_entryQuery, {'mediaId': track.remoteId});
    final entry = data['MediaList'] as Map<String, dynamic>;
    return _trackFromEntry(track.mangaId, track.remoteId, entry);
  }

  Track _trackFromEntry(int mangaId, int remoteId, Map<String, dynamic> e) {
    final media = e['media'] as Map<String, dynamic>;
    final title = media['title'] as Map<String, dynamic>;
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.aniList,
      remoteId: remoteId,
      libraryId: e['id'] as int?,
      title: (title['romaji'] ??
              title['english'] ??
              title['native'] ??
              '<untitled>') as String,
      lastChapterRead: ((e['progress'] as num?) ?? 0).toDouble(),
      totalChapters: (media['chapters'] as int?) ?? 0,
      status: _statusFromAniList(e['status'] as String?),
      score: ((e['score'] as num?) ?? 0).toDouble(),
      remoteUrl: media['siteUrl'] as String? ??
          '$_baseUrl/manga/$remoteId',
      startDate: _dateFromAniList(e['startedAt']),
      finishDate: _dateFromAniList(e['completedAt']),
      private: e['private'] as bool? ?? false,
    );
  }

  static const String _updateEntryMutation = r'''
    mutation Update($mediaId: Int, $status: MediaListStatus, $progress: Int, $score: Float, $private: Boolean, $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) {
      SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, scoreRaw: $score, private: $private, startedAt: $startedAt, completedAt: $completedAt) {
        id status progress score private
      }
    }
  ''';

  /// AniList's `FuzzyDateInput`, verbatim from Kotlin `AnilistApi.createDate`:
  /// a local-time y/m/d, or all three null for "unset". The entry query above
  /// already reads these back into [Track.startDate] / [Track.finishDate];
  /// nothing ever wrote them, so a Mohyeong-only reader's AniList profile
  /// never got a start or finish date.
  static Map<String, int?> _fuzzyDate(int epochMillis) {
    if (epochMillis == 0) {
      return const {'year': null, 'month': null, 'day': null};
    }
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    return {'year': d.year, 'month': d.month, 'day': d.day};
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    await _gql(_updateEntryMutation, {
      'mediaId': track.remoteId,
      'status': _statusToAniList(track.status),
      'progress': track.lastChapterRead.toInt(),
      // AniList stores POINT_100 internally; the score field is set raw.
      'score': (track.score * 10).toInt(),
      'private': track.private,
      'startedAt': _fuzzyDate(track.startDate),
      'completedAt': _fuzzyDate(track.finishDate),
    });
    return track;
  }

  String _statusToAniList(int status) {
    switch (status) {
      case TrackStatus.reading:
        return 'CURRENT';
      case TrackStatus.completed:
        return 'COMPLETED';
      case TrackStatus.onHold:
        return 'PAUSED';
      case TrackStatus.dropped:
        return 'DROPPED';
      case TrackStatus.planToRead:
        return 'PLANNING';
      case TrackStatus.rereading:
        return 'REPEATING';
      default:
        return 'PLANNING';
    }
  }

  int _statusFromAniList(String? s) {
    switch (s) {
      case 'CURRENT':
        return TrackStatus.reading;
      case 'COMPLETED':
        return TrackStatus.completed;
      case 'PAUSED':
        return TrackStatus.onHold;
      case 'DROPPED':
        return TrackStatus.dropped;
      case 'PLANNING':
        return TrackStatus.planToRead;
      case 'REPEATING':
        return TrackStatus.rereading;
      default:
        return TrackStatus.planToRead;
    }
  }

  int _dateFromAniList(Object? raw) {
    if (raw is! Map) return 0;
    final y = raw['year'];
    final m = raw['month'];
    final d = raw['day'];
    if (y is! int || m is! int || d is! int) return 0;
    return DateTime(y, m, d).millisecondsSinceEpoch;
  }
}
