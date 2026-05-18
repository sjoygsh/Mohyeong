# Changelog

All notable changes to **Mohyeong** will be documented in this file.

The format is a modified version of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
- `Added` - for new features.
- `Changed` - for changes in existing functionality.
- `Improved` - for enhancement or optimization in existing functionality.
- `Removed` - for now removed features.
- `Fixed` - for any bug fixes.
- `Other` - for technical stuff.

## [Unreleased]

## [0.19.14]

### Fixed
- **Cloudflare auto-solve no longer burns `cf_clearance` on interactive Turnstile pages.** Mohyeong's expanded body-marker list (`"Just a moment"`, `cf_chl_opt`, `/cdn-cgi/challenge-platform/`, etc.) was firing the hidden auto-solve WebView on Turnstile challenges that fundamentally can't be auto-solved (they require a human checkbox click). The hidden WebView would clear the user's existing `cf_clearance` cookie, fail after the 30s timeout, and leave the user trapped in an apparent "verify checkbox loop" on sites like toongod, kunmanga, manhwaclan, readallcomics, aquamanga, hivetoons. Auto-solve is now narrowed to the old non-interactive JS challenge only, matching upstream Mihon's behaviour.
- **Manual WebView no longer hijacks Cloudflare's Turnstile iframe.** `shouldOverrideUrlLoading` now skips subframe navigations, so the Turnstile iframe (`challenges.cloudflare.com`) can complete its verification handoff without the main frame getting redirected to the iframe URL.
- **`cf_clearance` cookie is flushed to disk when the WebView Activity closes**, so it survives a process kill instead of waiting for Android's periodic cookie writeback.

## [0.19.13]

### Improved
- Sync credential encryption is faster on hot paths: the Keystore `SecretKey` is now cached after first lookup (avoids a JNI keystore call per encrypt/decrypt), and decrypt no longer allocates two intermediate `ByteArray`s for the IV/ciphertext split.

## [0.19.12]

### Fixed
- Local source "Local source guide" link and the overflow-menu "Help" button no longer point at Mihon's docs — both now open the Mohyeong help page's new `#local-source` section.

### Added
- New `Local Source` section in the help page covering the `local/<series>/<chapter>` folder layout, optional `details.json` metadata, and cover image conventions.

## [0.19.11]

### Security
- Sync credentials (WebDAV password & username, SyncYomi API key, Google Drive access token, Dropbox personal access token) are now encrypted at rest using Android Keystore-backed AES-256/GCM. Existing plaintext credentials are migrated automatically on first launch.
- WebDAV sync now rejects non-`https://` server URLs in settings to prevent credentials being sent in cleartext. Existing configurations are not modified — only new entries are validated.

## [0.19.10]

### Fixed
- More tab header logo rendering as a white blob (reverted to a monochrome silhouette that respects the theme tint).
- Notification status-bar icons (library update, backup, extension install) rendering as a solid shape.
- Splash screen logo rendering.
- Help page deep links from in-app buttons (`#getting-started`, `#source-migration`, `#library-faq`, `#storage`, `#troubleshooting`) landing at the top of the page instead of the relevant section.

### Improved
- Cloudflare auto-solve setting now uses plain-English wording instead of the `cf_clearance` jargon.
- Enhanced trackers info text now explains that the section is populated by installing matching source extensions (Komga, Kavita, Suwayomi).

## [0.19.9]

### Other
- Initial Mohyeong release, forked from [Mihon](https://github.com/mihonapp/mihon) v0.19.9.
- Added linked sources feature.
- Added multi-backend cloud sync (SyncYomi, WebDAV, Google Drive, Dropbox).
- Added per-row timestamp-based conflict resolution.

For prior history, see the [Mihon changelog](https://github.com/mihonapp/mihon/blob/main/CHANGELOG.md).
