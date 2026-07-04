# CLAUDE.md — Mohyeong

Mohyeong is a Flutter 1:1 rewrite of Tachiyomi/Mihon. The repo root is the
Kotlin Mohyeong fork; the Flutter app lives in `flutter/`. Detailed session
state lives in Claude's machine-local memory — this file is the standing rules.

## Scope & safety
- Work only inside: this project directory, the session scratchpad, and
  Claude's own memory dir under `~/.claude/`. Never create, modify, or delete
  anything outside those without saying so in chat first and waiting for my
  reply.
- Same on the phone: touch only the Mohyeong-related apps
  (`app.mohyeong.dev` = debug Flutter app; `app.mohyeong` = Kotlin fork,
  reference only) and their data/files. No other apps, no device settings —
  in particular do NOT switch on auto-rotate. Leave the phone as you found it.
- Restorability is a major concern: before deleting or overwriting anything,
  make sure a way back exists (git history, a fresh backup). Never remove both
  the phone copies and the local copies of the extensions without taking a
  fresh backup first.

## Git
- Commit per logical chunk, directly on `main`. Trailer:
  `Co-Authored-By: <current working model> <noreply@anthropic.com>`.
- Push only when I ask.
- **Never push extensions to git.** `flutter/_ext_*.js`,
  `flutter/.tmp_manifests/`, and `extensions_backup/` stay untracked
  (gitignored); they live only in the working tree, `extensions_backup/`, and
  on the phone. Refresh `extensions_backup/` after extension edits.

## Subagents
- 1–2 subagents: Opus (latest). 3 or more: Sonnet (latest) — a large all-Opus
  batch previously blew the session token limit.

## Code
- Do NOT run `dart format` — the repo is not format-clean (it churns ~800
  lines of `manga_details_screen.dart`).
- Strict 1:1 parity with Mihon; honest wiring (no dead switches).
- Before committing Flutter changes: `flutter analyze lib/` must be clean and
  `flutter test` green; `node --check` any edited `_ext_*.js`.
