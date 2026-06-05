/// Domain + wire models for the in-app update checker.
///
/// 1:1 port of Mihon's release types:
/// - [Release] mirrors `tachiyomi.domain.release.model.Release`.
/// - [GithubRelease] / [GithubAsset] mirror the GitHub-API DTOs in
///   `tachiyomi.data.release.GithubRelease` (`tag_name`, `body`, `html_url`,
///   `assets[].browser_download_url`).
library;

/// Information about the latest release, decoupled from the GitHub wire shape.
/// Matches `Release(version, info, releaseLink, downloadLink)`.
class Release {
  const Release({
    required this.version,
    required this.info,
    required this.releaseLink,
    required this.downloadLink,
  });

  /// Raw tag name, e.g. `v0.1.2` (release) or `r1234` (preview).
  final String version;

  /// Changelog body (markdown). Mihon trims everything after the last
  /// `<!-->` marker and rewrites `@mentions` into links; we keep the raw
  /// body minus the trailing marker since the about screen only shows the
  /// version, not the changelog.
  final String info;

  /// `html_url` of the GitHub release page.
  final String releaseLink;

  /// Direct download URL of the matching APK asset (may be empty when no
  /// asset matches — the about-screen flow only needs [releaseLink]).
  final String downloadLink;
}

/// GitHub `releases/latest` payload. Field names mirror the SerialNames used
/// in Mihon's `GithubRelease` so the JSON maps directly.
class GithubRelease {
  const GithubRelease({
    required this.version,
    required this.info,
    required this.releaseLink,
    required this.assets,
  });

  /// `tag_name`
  final String version;

  /// `body`
  final String info;

  /// `html_url`
  final String releaseLink;

  /// `assets`
  final List<GithubAsset> assets;

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = (json['assets'] as List<dynamic>?) ?? const [];
    return GithubRelease(
      version: json['tag_name'] as String? ?? '',
      info: json['body'] as String? ?? '',
      releaseLink: json['html_url'] as String? ?? '',
      assets: rawAssets
          .whereType<Map<String, dynamic>>()
          .map(GithubAsset.fromJson)
          .toList(growable: false),
    );
  }
}

/// A single release asset (`name` + `browser_download_url`).
class GithubAsset {
  const GithubAsset({required this.name, required this.downloadLink});

  final String name;

  /// `browser_download_url`
  final String downloadLink;

  factory GithubAsset.fromJson(Map<String, dynamic> json) => GithubAsset(
        name: json['name'] as String? ?? '',
        downloadLink: json['browser_download_url'] as String? ?? '',
      );
}
