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
