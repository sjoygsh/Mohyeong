<div align="center">

<img src="app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="Mohyeong" width="100" />

# Mohyeong

### Enhanced Android Manga Reader

**Mohyeong** is an open-source fork of [Mihon](https://mihon.app) with additional features for power users — linked sources, multi-backend cloud sync, and smarter conflict resolution.

[![Latest Release](https://img.shields.io/github/v/release/sjoygsh/Mohyeong?style=flat-square&label=Download&color=c0392b)](https://github.com/sjoygsh/Mohyeong/releases/latest)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square)](LICENSE)
[![Android](https://img.shields.io/badge/Android-8.0%2B-green?style=flat-square)](https://github.com/sjoygsh/Mohyeong/releases)
[![Built with Claude AI](https://img.shields.io/badge/Built%20with-Claude%20AI-8a2be2?style=flat-square)](https://claude.ai)

[Website](https://sjoygsh.github.io/Mohyeong/) · [Documentation](https://sjoygsh.github.io/Mohyeong/help.html) · [Download](https://github.com/sjoygsh/Mohyeong/releases)

</div>

---

## About

Mohyeong (모형) is a fork of [Mihon](https://github.com/mihonapp/mihon), which continues the legacy of [Tachiyomi](https://github.com/tachiyomiorg/tachiyomi). It includes everything Mihon offers, plus exclusive enhancements developed with the assistance of **Claude AI (Anthropic)**.

> **Transparency notice:** The additional features in Mohyeong were designed and implemented with direct AI collaboration. This is intentional and not hidden.

---

## Features

### Mohyeong Exclusive

| Feature | Description |
|---|---|
| 🔗 **Linked Sources** | Attach multiple sources to one manga entry. Chapters from all linked sources merge into a single unified list. |
| ☁️ **Multi-Backend Sync** | Sync your library via **SyncYomi**, **WebDAV**, **Google Drive**, or **Dropbox**. |
| ⚖️ **Smart Conflict Resolution** | Per-row timestamp-based merging — the most recently changed data wins, not just the latest full snapshot. |
| 🔴 **Live Sync Status** | Reactive sync indicator powered by WorkManager flow — updates in real time, no polling. |

### From Mihon

- 📚 Automatic tracking with MyAnimeList, AniList, Kitsu, MangaUpdates, Shikimori, Bangumi
- 🎨 Multiple reading modes (webtoon, paged, vertical, continuous)
- 🔌 Hundreds of sources via the extension system
- 📁 Full backup and restore (`.tachibk` format — compatible with Mihon)
- 📂 Categories, bulk actions, smart library filters
- ⬇️ Offline downloads with queue management

---

## Download

Get the latest APK from the [Releases page](https://github.com/sjoygsh/Mohyeong/releases/latest).

**Requirements:** Android 8.0 (API 26) or higher · `arm64-v8a` recommended

The release APK uses package ID `app.mohyeong` — it will not conflict with Mihon (`app.mihon`) if both are installed.

---

## Sync Setup

Mohyeong supports four sync backends. All use the same bidirectional merge engine.

| Backend | Auth type | Self-hosted |
|---|---|---|
| SyncYomi | API key | ✅ |
| WebDAV | Username + password | ✅ |
| Google Drive | OAuth access token | ❌ |
| Dropbox | Personal access token | ❌ |

Enable in **More → Settings → Sync**. See the [full sync guide](https://sjoygsh.github.io/Mohyeong/help.html#sync-overview) for setup instructions.

---

## Building from Source

```bash
git clone https://github.com/sjoygsh/Mohyeong.git
cd Mohyeong

# Debug build
./gradlew assembleDebug

# Release build (requires signing config)
./gradlew assembleRelease
```

Requires Android Studio Iguana or newer and JDK 17+.

---

## Differences from Mihon

Mohyeong diverges from Mihon in the following areas:

- **Package ID:** `app.mohyeong` (vs `app.mihon`)
- **App name / branding:** Mohyeong (모형)
- **Linked sources:** new feature, not in upstream
- **Sync transports:** WebDAV, Google Drive, Dropbox added on top of SyncYomi
- **Conflict resolution:** per-row timestamp merge instead of last-write-wins
- **Sync status:** WorkManager flow (reactive) vs snapshot

Mohyeong backup files (`.tachibk`) are fully compatible with Mihon.

---

## Credits

- [Mihon](https://github.com/mihonapp/mihon) — upstream project (Apache 2.0)
- [Tachiyomi](https://github.com/tachiyomiorg/tachiyomi) — original project
- [Claude AI by Anthropic](https://claude.ai) — AI assistance for feature development

---

## License

```
Copyright 2024 Mohyeong Contributors
Copyright 2024 Mihon Contributors
Copyright 2015 Javier Tomás

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0
```
