import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/app_http_client.dart';
import 'track_credential_store.dart';
import 'tracker.dart';
import 'trackers/anilist.dart';
import 'trackers/kitsu.dart';
import 'trackers/komga.dart';
import 'trackers/manga_updates.dart';
import 'trackers/myanimelist.dart';
import 'trackers/shikimori.dart';
import 'trackers/stub_trackers.dart';

/// Provides the single shared navigator key all trackers use to surface the
/// OAuth webview. Wired into [MaterialApp.navigatorKey] from main.dart.
final trackerNavigatorKeyProvider =
    Provider<GlobalKey<NavigatorState>>((ref) => GlobalKey<NavigatorState>());

final trackCredentialStoreProvider =
    Provider<TrackCredentialStore>((ref) => TrackCredentialStore());

/// Registry of every tracker the app knows about. Equivalent to Mihon's
/// `TrackerManager`. Tracker ids never change once shipped — see
/// [TrackerIds]. Adding a new tracker means: define an id constant, add an
/// implementation, register it here.
class TrackerRegistry {
  TrackerRegistry(this._trackers) {
    _byId = {for (final t in _trackers) t.id: t};
  }

  final List<Tracker> _trackers;
  late final Map<int, Tracker> _byId;

  List<Tracker> get all => List.unmodifiable(_trackers);

  Tracker? byId(int id) => _byId[id];
}

final trackerRegistryProvider = Provider<TrackerRegistry>((ref) {
  final credentials = ref.watch(trackCredentialStoreProvider);
  final navigatorKey = ref.watch(trackerNavigatorKeyProvider);
  final http = ref.watch(appHttpClientProvider);
  final trackers = <Tracker>[
    MyAnimeListTracker(credentials: credentials, navigatorKey: navigatorKey),
    AniListTracker(credentials: credentials, navigatorKey: navigatorKey),
    KitsuTracker(credentials: credentials, navigatorKey: navigatorKey),
    ShikimoriTracker(credentials: credentials, navigatorKey: navigatorKey),
    MangaUpdatesTracker(
      credentials: credentials,
      navigatorKey: navigatorKey,
    ),
    KomgaTracker(
      credentials: credentials,
      navigatorKey: navigatorKey,
    ),
    SuwayomiTracker(credentials: credentials),
  ];
  for (final t in trackers) {
    t.attachDio(http.dio);
  }
  return TrackerRegistry(trackers);
});
