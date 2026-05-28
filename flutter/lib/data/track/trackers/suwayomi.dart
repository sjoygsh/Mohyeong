import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../domain/track/model/track.dart';
import '../../../domain/track/model/tracker.dart';
import '../../../presentation/track/credentials_login_screen.dart';
import '../track_credential_store.dart';
import '../tracker.dart';

/// Suwayomi tracker — points at the user's self-hosted Suwayomi-Server.
///
/// Auth is HTTP Basic against `/api/graphql`. In Mihon, Suwayomi is an
/// "enhanced" tracker that inherits its server URL + credentials from the
/// installed Tachidesk source extension. Mohyeong's source extension layer
/// is JS-based and doesn't carry that linkage, so this tracker is
/// standalone: the user configures the server directly at login (same
/// pattern as [KomgaTracker]).
///
/// On update: mark every still-unread chapter with chapterNumber ≤
/// `track.lastChapterRead` as read, then ask the server to recompute
/// progress via the `trackProgress` mutation, then re-fetch the manga
/// to get the canonical post-update status.
class SuwayomiTracker extends Tracker {
  SuwayomiTracker({
    required this.credentials,
    required this.navigatorKey,
  }) : super(
          TrackerIds.suwayomi,
          'Suwayomi',
          TrackerCategory.advanced,
        );

  // Suwayomi has no distinct list a manga is "on" — status is derived
  // from unreadCount vs totalCount on the server.
  static const int _suwayomiUnread = 1;
  static const int _suwayomiReading = 2;
  static const int _suwayomiCompleted = 3;

  final TrackCredentialStore credentials;
  final GlobalKey<NavigatorState> navigatorKey;
  Dio? _dio;

  @override
  bool get supportsServerUrl => true;

  @override
  Future<bool> get isLoggedIn =>
      credentials.isAuthenticated(TrackerIds.suwayomi);

  @override
  void attachDio(Dio dio) {
    _dio = dio;
  }

  Dio get _http {
    final d = _dio;
    if (d == null) throw StateError('SuwayomiTracker.dio not attached');
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
          title: 'Log in to Suwayomi',
          includeServerUrl: true,
          serverUrlLabel: 'Suwayomi server URL',
          serverUrlHint: 'http://suwayomi.local:4567',
          helperText: 'Enter your Suwayomi server URL and (if your server '
              'requires basic auth) the username/password. Leave the '
              'username/password blank for open LAN installs.',
        ),
      ),
    );
    if (result == null) {
      throw TrackerException('Suwayomi login cancelled');
    }
    final server = result.serverUrl?.trim() ?? '';
    if (server.isEmpty) {
      throw TrackerException('Suwayomi login: server URL is required');
    }
    final normalised = _stripTrailingSlash(server);
    // Empty username+password is supported — many Suwayomi installs run
    // open on the LAN with no auth at all.
    final basic = (result.username.isEmpty && result.password.isEmpty)
        ? ''
        : base64Encode(utf8.encode('${result.username}:${result.password}'));
    // Verify we can reach the GraphQL endpoint before persisting.
    final probe = await _http.post<String>(
      '$normalised/api/graphql',
      data: jsonEncode({'query': '{ __typename }'}),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (basic.isNotEmpty) 'Authorization': 'Basic $basic',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (probe.statusCode != 200) {
      throw TrackerException(
        'Suwayomi login failed (${probe.statusCode})',
        response: probe.data,
      );
    }
    await credentials.writeCredential(
      TrackerIds.suwayomi,
      TrackerCredential(
        accessToken: basic,
        userdata: normalised,
      ),
    );
  }

  @override
  Future<void> logout() => credentials.clear(TrackerIds.suwayomi);

  /// Returns (serverUrl, basicAuth) for outbound requests. Basic auth may
  /// be the empty string for open Suwayomi servers — callers should check.
  Future<(String, String)> _ctx() async {
    final cred = await credentials.readCredential(TrackerIds.suwayomi);
    if (cred == null) throw TrackerNotAuthenticated(name);
    final server = cred.userdata;
    if (server == null || server.isEmpty) {
      throw TrackerException(
        'Suwayomi: stored credentials missing server URL',
      );
    }
    return (server, cred.accessToken);
  }

  Future<Map<String, dynamic>> _graphql(
    String query,
    Map<String, Object?> variables,
  ) async {
    final (server, basic) = await _ctx();
    final response = await _http.post<String>(
      '$server/api/graphql',
      data: jsonEncode({'query': query, 'variables': variables}),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (basic.isNotEmpty) 'Authorization': 'Basic $basic',
        },
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw TrackerException(
        'Suwayomi request failed (${response.statusCode})',
        response: response.data,
      );
    }
    final body = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw TrackerException(
        'Suwayomi GraphQL error: ${jsonEncode(errors)}',
      );
    }
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  static const String _mangaFragment = r'''
fragment MangaFragment on MangaType {
  id
  title
  thumbnailUrl
  description
  status
  url
  chapters { totalCount }
  latestReadChapter { lastReadAt chapterNumber }
  unreadCount
}
''';

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    final (server, _) = await _ctx();
    final gql = '''
query SearchManga(\$query: String!) {
  mangas(condition: {inLibrary: true}, filter: {title: {includes: \$query}}) {
    nodes { ...MangaFragment }
  }
}
$_mangaFragment
''';
    final data = await _graphql(gql, {'query': query});
    final nodes = ((data['mangas'] as Map?)?['nodes'] as List?) ?? const [];
    return nodes.map((raw) {
      final manga = raw as Map<String, dynamic>;
      final id = (manga['id'] as num).toInt();
      final thumb = manga['thumbnailUrl'] as String? ?? '';
      return TrackSearchResult(
        remoteId: id,
        title: (manga['title'] as String?)?.trim() ?? '<untitled>',
        totalChapters:
            ((manga['chapters'] as Map?)?['totalCount'] as num?)?.toInt() ?? 0,
        coverUrl: thumb.startsWith('http') ? thumb : '$server$thumb',
        summary: manga['description'] as String?,
        publishingStatus: manga['status'] as String?,
        publishingType: null,
        startDate: null,
        score: null,
        remoteUrl: '$server/manga/$id',
      );
    }).toList(growable: false);
  }

  @override
  Future<Track> bind(int mangaId, TrackSearchResult searchResult) async {
    // Suwayomi has no "binding" — the manga either exists in the user's
    // library on the server or it doesn't. Synthesise a Track so the
    // local DB has somewhere to hang progress + tracking_url.
    return Track(
      id: -1,
      mangaId: mangaId,
      trackerId: TrackerIds.suwayomi,
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
    final remoteId = track.remoteId;
    final gql = '''
query GetManga(\$mangaId: Int!) {
  manga(id: \$mangaId) { ...MangaFragment }
}
$_mangaFragment
''';
    final data = await _graphql(gql, {'mangaId': remoteId});
    final manga = data['manga'] as Map<String, dynamic>?;
    if (manga == null) {
      throw TrackerException(
        'Suwayomi refresh: manga $remoteId not found on server',
      );
    }
    final totalCount =
        ((manga['chapters'] as Map?)?['totalCount'] as num?)?.toInt() ?? 0;
    final unreadCount = (manga['unreadCount'] as num?)?.toInt() ?? totalCount;
    final lastRead = ((manga['latestReadChapter'] as Map?)?['chapterNumber']
                as num?)
            ?.toDouble() ??
        0.0;
    final suwayomiStatus = unreadCount == totalCount
        ? _suwayomiUnread
        : (unreadCount == 0 ? _suwayomiCompleted : _suwayomiReading);
    return track.copyWith(
      lastChapterRead: lastRead,
      totalChapters: totalCount,
      status: _statusFromSuwayomi(suwayomiStatus),
      title: (manga['title'] as String?)?.trim() ?? track.title,
    );
  }

  @override
  Future<Track> update(Track track, {bool didReadChapter = false}) async {
    final remoteId = track.remoteId;
    final cutoff = track.lastChapterRead + 0.001;

    // 1. Collect unread chapter ids on the server whose chapterNumber is
    //    at or below our local last-read mark.
    final unreadGql = r'''
query GetUnreadChapters($mangaId: Int!) {
  chapters(condition: {mangaId: $mangaId, isRead: false}) {
    nodes { id chapterNumber }
  }
}
''';
    final unreadData = await _graphql(unreadGql, {'mangaId': remoteId});
    final nodes =
        ((unreadData['chapters'] as Map?)?['nodes'] as List?) ?? const [];
    final ids = <int>[
      for (final node in nodes.cast<Map<String, dynamic>>())
        if (((node['chapterNumber'] as num?)?.toDouble() ?? double.infinity) <=
            cutoff)
          (node['id'] as num).toInt(),
    ];

    // 2. Bulk-mark them as read (skip the call if nothing to do).
    if (ids.isNotEmpty) {
      const markGql = r'''
mutation MarkChaptersRead($chapters: [Int!]!) {
  updateChapters(input: {ids: $chapters, patch: {isRead: true}}) { __typename }
}
''';
      await _graphql(markGql, {'chapters': ids});
    }

    // 3. Ask the server to recompute its derived progress for this manga
    //    so the next refresh returns the right unreadCount / status.
    const trackGql = r'''
mutation TrackManga($mangaId: Int!) {
  trackProgress(input: {mangaId: $mangaId}) { __typename }
}
''';
    await _graphql(trackGql, {'mangaId': remoteId});

    // 4. Re-read the canonical state from the server.
    return refresh(track);
  }

  int _statusFromSuwayomi(int suwayomiStatus) {
    switch (suwayomiStatus) {
      case _suwayomiCompleted:
        return TrackStatus.completed;
      case _suwayomiReading:
        return TrackStatus.reading;
      case _suwayomiUnread:
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
