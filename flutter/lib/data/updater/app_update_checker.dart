/// In-app update checker. 1:1 port of Mihon's update flow, collapsed into a
/// single class because the Flutter app is a plain release build (non-FOSS,
/// non-preview) so the build-flavor branching in the Kotlin source reduces to
/// the release path:
///
/// - `AppUpdateChecker` (the GitHub repo it queries + the entry point),
/// - `tachiyomi.data.release.ReleaseServiceImpl.latest` (the GitHub API call),
/// - `tachiyomi.domain.release.interactor.GetApplicationRelease.await`
///   (the 3-days-between-checks throttle + the version-compare logic).
///
/// Deliberately NOT ported: the notification subsystem (`AppUpdateNotifier`)
/// and APK auto-download — those have no Flutter equivalent yet. The UI just
/// surfaces the result and offers a button to open the release page.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/app_http_client.dart';
import 'release.dart';

/// GitHub repo queried for releases. Mirrors `GITHUB_REPO` in
/// `AppUpdateChecker.kt` (release, non-preview value).
const githubRepo = 'sjoygsh/Mohyeong';

/// SharedPreferences key for the last update-check timestamp (epoch millis).
/// Mirrors Mihon VERBATIM: `Preference.appStateKey("last_app_check")` expands
/// to the `__APP_STATE_` prefix + `last_app_check`. Replicated exactly so a
/// settings import from the Kotlin app carries the value across.
const lastAppCheckKey = '__APP_STATE_last_app_check';

/// Minimum gap between automatic checks. Mihon limits to once every 3 days
/// (`GetApplicationRelease`: `lastChecked.plus(3, ChronoUnit.DAYS)`).
const _checkInterval = Duration(days: 3);

/// Result of an update check, mirroring
/// `GetApplicationRelease.Result` (minus `OsTooOld`, which Mihon has
/// commented out).
sealed class AppUpdateResult {
  const AppUpdateResult();
}

/// A newer release than the installed build is available.
class NewUpdate extends AppUpdateResult {
  const NewUpdate(this.release);
  final Release release;
}

/// No newer release (either up to date, throttled, or no asset).
class NoNewUpdate extends AppUpdateResult {
  const NoNewUpdate();
}

class AppUpdateChecker {
  AppUpdateChecker(this._http);

  final AppHttpClient _http;

  /// Checks the latest GitHub release. When [forceCheck] is false the call is
  /// throttled to at most once per [_checkInterval] (returns [NoNewUpdate]
  /// without hitting the network if checked too recently) — matching
  /// `GetApplicationRelease.await`.
  Future<AppUpdateResult> checkForUpdate({bool forceCheck = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // Limit checks to once every 3 days at most.
    final lastChecked =
        DateTime.fromMillisecondsSinceEpoch(prefs.getInt(lastAppCheckKey) ?? 0);
    final nextCheckTime = lastChecked.add(_checkInterval);
    if (!forceCheck && now.isBefore(nextCheckTime)) {
      return const NoNewUpdate();
    }

    final release = await _latest();
    if (release == null) return const NoNewUpdate();

    await prefs.setInt(lastAppCheckKey, now.millisecondsSinceEpoch);

    final info = await PackageInfo.fromPlatform();
    final isNew = _isNewVersion(info.version, release.version);
    return isNew ? NewUpdate(release) : const NoNewUpdate();
  }

  /// Fetches `releases/latest` from the GitHub API and maps it to [Release].
  /// Mirrors `ReleaseServiceImpl.latest` (release path). Returns null on any
  /// network/parse failure so the caller degrades to "no update".
  Future<Release?> _latest() async {
    try {
      final response = await _http.dio.get<dynamic>(
        'https://api.github.com/repos/$githubRepo/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is! Map) return null;
      final gh = GithubRelease.fromJson(Map<String, dynamic>.from(data));

      // Mihon trims everything after the last `<!-->` changelog marker.
      final info = gh.info.contains('<!-->')
          ? gh.info.substring(0, gh.info.lastIndexOf('<!-->'))
          : gh.info;

      return Release(
        version: gh.version,
        info: info,
        releaseLink: gh.releaseLink,
        downloadLink: _downloadLink(gh) ?? '',
      );
    } on DioException {
      return null;
    }
  }

  /// Picks an APK asset to surface as the download link. The Flutter build is
  /// a single universal APK, so we just take the first asset (Mihon does ABI
  /// matching, which has no analogue here). Returns null if there are none.
  String? _downloadLink(GithubRelease release) =>
      release.assets.isEmpty ? null : release.assets.first.downloadLink;

  /// Whether [versionTag] (e.g. `v1.2.3`) is newer than the installed
  /// [versionName]. Direct port of `GetApplicationRelease.isNewVersion`
  /// (release branch): strip any non-digit/non-dot prefix, then scan the old
  /// version's segments left-to-right and return true on the FIRST index
  /// where the new segment is greater.
  ///
  /// NOTE: this mirrors Mihon's exact (quirky) semantics — it does NOT
  /// short-circuit to false when an earlier new segment is lower, it only
  /// looks for any greater segment. The one hardening added over the Kotlin
  /// source is the bounds guard on [newSemVer]: Mihon indexes
  /// `newSemVer[index]` directly and would throw if the new tag has fewer
  /// segments than the installed version; we treat a missing segment as 0.
  bool _isNewVersion(String versionName, String versionTag) {
    final newVersion = versionTag.replaceAll(RegExp(r'[^\d.]'), '');
    final oldVersion = versionName.replaceAll(RegExp(r'[^\d.]'), '');

    final newSemVer = _parseSegments(newVersion);
    final oldSemVer = _parseSegments(oldVersion);

    for (var i = 0; i < oldSemVer.length; i++) {
      final newSeg = i < newSemVer.length ? newSemVer[i] : 0;
      if (newSeg > oldSemVer[i]) return true;
    }
    return false;
  }

  List<int> _parseSegments(String version) => version
      .split('.')
      .where((s) => s.isNotEmpty)
      .map((s) => int.tryParse(s) ?? 0)
      .toList(growable: false);
}

/// Riverpod handle for the checker, wired to the shared HTTP client.
final appUpdateCheckerProvider = Provider<AppUpdateChecker>((ref) {
  return AppUpdateChecker(ref.watch(appHttpClientProvider));
});
