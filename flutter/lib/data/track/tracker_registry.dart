import 'package:dio/dio.dart';
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
import 'trackers/suwayomi.dart';

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

/// Builds the registry from its three collaborators. Split out of the
/// provider so the delayed-tracking retry job — which runs in the workmanager
/// isolate, where there is no Riverpod — gets the SAME tracker list instead of
/// a second copy that could drift as trackers are added.
TrackerRegistry buildTrackerRegistry({
  required TrackCredentialStore credentials,
  required GlobalKey<NavigatorState> navigatorKey,
  required Dio dio,
}) {
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
    SuwayomiTracker(
      credentials: credentials,
      navigatorKey: navigatorKey,
    ),
  ];
  for (final t in trackers) {
    t.attachDio(dio);
  }
  return TrackerRegistry(trackers);
}

final trackerRegistryProvider = Provider<TrackerRegistry>((ref) {
  return buildTrackerRegistry(
    credentials: ref.watch(trackCredentialStoreProvider),
    navigatorKey: ref.watch(trackerNavigatorKeyProvider),
    dio: ref.watch(appHttpClientProvider).dio,
  );
});
