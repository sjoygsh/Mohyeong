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

## [0.19.17]

### Added
- **"Make primary" — swap which linked source owns the cluster.** Each entry in the Linked sources dialog now has a star icon next to the remove button. Tapping it promotes that linked manga to the primary of the cluster: its title, cover, and description take over the library entry, and the old primary becomes a linked entry alongside the rest. Useful when you'd rather have a different source's metadata without re-linking from scratch. If the target isn't favorited yet, it's added to your default category as part of the swap so the library entry doesn't vanish.

### Fixed
- **Unfavoriting the primary now offers to clear downloads from every linked source.** Previously the snackbar prompt and the delete action only walked the primary's per-source download folder, leaving the linked-source folders behind as orphaned downloads. Both `hasDownloads` (whether the snackbar prompt appears) and `deleteDownloads` (what the "Delete" action actually clears) now cover every linked manga, each resolved against its real source.
- **Updates tab attributes linked-source chapter entries to their cluster's primary.** When a linked source publishes a new chapter, the Updates row now shows the primary's title and cover (instead of the linked source's), and tapping the cover navigates to the primary's library entry instead of a separate linked-only screen. Opening the chapter still routes through the chapter's real (linked) source, so the page loads from the correct mirror.

### Other
- Backup / restore for linked sources was already wired up via `BackupMangaLink` (ProtoNumber 107) and `restoreMangaLinks`. Verified that links are preserved across backup round-trips and that missing manga (e.g. an uninstalled source) is skipped gracefully.
- "Open in browser" / "Share" from a chapter already routes to the correct source — `ReaderViewModel.getChapterUrl()` resolves the source via `manga.source` on the chapter's owning manga, so linked-source chapters share/open with their own source's URL, not the primary's.

## [0.19.16]

### Fixed
- **Merged chapter list across linked sources is now sorted correctly.** With the linked-sources merge in 0.19.15, chapters from different sources would interleave nonsensically (e.g. primary's Ch.27 appearing above linked's Ch.28) because each source assigns its own `sourceOrder=0` to its newest chapter, and the default "source order" sort can't compare across sources. Merged chapters are now resequenced by chapter number for display, so the existing sort produces the expected order. Side effect: the spurious "Missing N chapters" separator between out-of-order chapters is gone.

## [0.19.15]

### Changed
- **Linked sources now actually merge into one library entry, as the help page has always promised.** Previously, "linking" two mangas only enabled a fallback chapter list if the primary source failed; both entries stayed visible in the library with separate chapter lists. Now:
  - **Library updates walk every linked source** under the primary manga. When Asura's mirror of *X* gets a new chapter, it appears under the ManhwaTop entry in your library — even if ManhwaTop itself hasn't updated.
  - **The chapter list on the primary entry is a merged, deduped view** of the primary + every linked source. Dedupe is by recognized chapter number; the primary always wins ties, then the earliest-linked source fills in any gaps the primary is missing.
  - **Marking a chapter read mirrors across linked sources by chapter number.** Marking ManhwaTop's Ch.10 as read also marks Asura's Ch.10 as read, so switching the primary source later doesn't reset your progress.
  - **Downloads go to the correct per-source folder.** Chapters from linked sources are downloaded against their own source's download path with their own URL — they're not silently dumped into the primary's folder.
  - **Pull-to-refresh on the manga screen** now always walks every linked source, not just when the primary fetch errors out.

### Other
- Metadata (cover, title, description) still comes from the primary source only. Migrating between linked sources to change which entry is "primary" is not yet supported in-app — for now, unlink and relink in the opposite direction.

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
