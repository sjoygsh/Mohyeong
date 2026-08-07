import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/track/track_credential_store.dart';
import 'package:mohyeong/data/track/trackers/anilist.dart';
import 'package:mohyeong/data/track/trackers/kitsu.dart';
import 'package:mohyeong/domain/track/model/track.dart';
import 'package:mohyeong/domain/track/model/tracker.dart';

/// What we actually put on the wire.
///
/// Verifying the dates against a live AniList/Kitsu account needs credentials
/// nobody should be inventing — you cannot make up an OAuth token, and signing
/// up fake accounts to poke someone else's API is not a test. What CAN be
/// pinned without an account is our half of the contract: the request body.
/// So the tracker is driven with a fake token and a fake HTTP adapter that
/// captures the request and answers with a canned response, and the assertions
/// are on the JSON that was about to be sent.
///
/// This proves the payload carries the dates in the fork's shape. It does NOT
/// prove AniList accepts it — only a real account does that.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.reply);

  final String reply;
  final List<RequestOptions> requests = [];
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data;
    bodies.add(data is String ? data : jsonEncode(data));
    return ResponseBody.fromString(
      reply,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Track _track({
  required int trackerId,
  int startDate = 0,
  int finishDate = 0,
}) =>
    Track(
      id: 1,
      mangaId: 1,
      trackerId: trackerId,
      remoteId: 4242,
      libraryId: 99,
      title: 'A Series',
      lastChapterRead: 12,
      totalChapters: 0,
      status: TrackStatus.reading,
      score: 8,
      remoteUrl: '',
      startDate: startDate,
      finishDate: finishDate,
      private: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fake token, so `_gql` gets past its not-authenticated guard.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read') return 'fake-access-token';
        if (call.method == 'readAll') {
          return <String, String>{'fake': 'fake'};
        }
        return null;
      },
    );
  });

  test('AniList sends startedAt / completedAt as a FuzzyDateInput', () async {
    final adapter = _CapturingAdapter(
      jsonEncode({
        'data': {
          'SaveMediaListEntry': {
            'id': 99,
            'status': 'CURRENT',
            'progress': 12,
            'score': 8,
            'private': false,
          },
        },
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final tracker = AniListTracker(
      credentials: TrackCredentialStore(),
      navigatorKey: GlobalKey<NavigatorState>(),
    )..attachDio(dio);

    final start = DateTime(2026, 3, 14);
    final finish = DateTime(2026, 8, 1);
    await tracker.update(
      _track(
        trackerId: TrackerIds.aniList,
        startDate: start.millisecondsSinceEpoch,
        finishDate: finish.millisecondsSinceEpoch,
      ),
    );

    expect(adapter.bodies, hasLength(1));
    final sent = jsonDecode(adapter.bodies.single) as Map<String, dynamic>;
    final vars = sent['variables'] as Map<String, dynamic>;

    // The dates are there, in AniList's y/m/d object form.
    expect(vars['startedAt'], {'year': 2026, 'month': 3, 'day': 14});
    expect(vars['completedAt'], {'year': 2026, 'month': 8, 'day': 1});
    // And the mutation actually declares them, or the variables are ignored.
    expect(sent['query'], contains(r'$startedAt: FuzzyDateInput'));
    expect(sent['query'], contains(r'$completedAt: FuzzyDateInput'));
    expect(sent['query'], contains('startedAt: \$startedAt'));
    expect(sent['query'], contains('completedAt: \$completedAt'));
    // Progress still rides along — the dates must not have displaced it.
    expect(vars['progress'], 12);
  });

  test('AniList sends explicit nulls when the dates are unset', () async {
    // A y/m/d of zeroes would stamp year 0 on the account; the fork sends
    // three nulls, which is how AniList spells "no date".
    final adapter = _CapturingAdapter(
      jsonEncode({
        'data': {
          'SaveMediaListEntry': {'id': 99, 'status': 'CURRENT', 'progress': 12},
        },
      }),
    );
    final tracker = AniListTracker(
      credentials: TrackCredentialStore(),
      navigatorKey: GlobalKey<NavigatorState>(),
    )..attachDio(Dio()..httpClientAdapter = adapter);

    await tracker.update(_track(trackerId: TrackerIds.aniList));

    final vars = (jsonDecode(adapter.bodies.single)
        as Map<String, dynamic>)['variables'] as Map<String, dynamic>;
    expect(vars['startedAt'], {'year': null, 'month': null, 'day': null});
    expect(vars['completedAt'], {'year': null, 'month': null, 'day': null});
  });

  test('Kitsu sends startedAt / finishedAt in its own format', () async {
    final adapter = _CapturingAdapter(
      jsonEncode({
        'data': {
          'id': '99',
          'type': 'libraryEntries',
          'attributes': {'progress': 12, 'status': 'current'},
        },
      }),
    );
    final tracker = KitsuTracker(
      credentials: TrackCredentialStore(),
      navigatorKey: GlobalKey<NavigatorState>(),
    )..attachDio(Dio()..httpClientAdapter = adapter);

    final start = DateTime(2026, 3, 14, 9, 5, 7, 42);
    await tracker.update(
      _track(
        trackerId: TrackerIds.kitsu,
        startDate: start.millisecondsSinceEpoch,
      ),
    );

    final sent = jsonDecode(adapter.bodies.single) as Map<String, dynamic>;
    final attrs = ((sent['data'] as Map<String, dynamic>)['attributes'])
        as Map<String, dynamic>;
    expect(attrs['startedAt'], '2026-03-14T09:05:07.042Z');
    // Unset stays null rather than becoming 1970.
    expect(attrs['finishedAt'], isNull);
    expect(attrs['progress'], 12);
  });
}
