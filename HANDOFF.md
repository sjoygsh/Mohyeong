# Mohyeong v1.0 — Extensions + Perf Handoff (2026-06-27)

> Self-contained handoff for continuing on a new device. (The richer running
> notes live in Claude's machine-local memory, which does NOT travel — this file
> is the transferable record. Everything below is committed to git.)

## What this is
Mohyeong is a Flutter rewrite of Tachiyomi/Mihon (strict 1:1 parity goal). This
work stream builds **JS "source extensions"** (one `.js` per manga site) and
the host plumbing they need, plus perf work. Extension files: `flutter/_ext_*.js`.

### How extensions load / are side-loaded (dev)
On device they live at `app_flutter/extensions/<id>/{source.js, manifest.json}`
(debuggable package: **`app.mohyeong.dev`**; the `eu.kanade.*` packages are the
PARALLEL Kotlin Mihon's APK extensions — ignore them). Side-load:
```
adb push F:/Mohyeong/mihon/flutter/_ext_<id>.js /data/local/tmp/x.js
adb shell run-as app.mohyeong.dev cp /data/local/tmp/x.js app_flutter/extensions/<id>/source.js
```
manifest.json is one-line JSON `{id,name,lang,base_url,version_code,supports_latest}`.
Generate it by eval-ing the JS with stubbed `http`/`console` and reading
`__extension.manifest` (see the node harness below). **Force-stop + relaunch to
reload changed source** (the runtime caches loaded code).

### JS extension contract
Each file registers a global `__extension` = `{ manifest, popular(page),
latest(page), search(query,page), details(manga), chapters(manga), pages(chapter),
chapterUrl(chapter) }`. Host globals on the worker isolate: `http.get(url,opts)` /
`http.post(url,opts)` (Promise of `{ok,status,body,...}`), `console`. Listing
methods return `{mangas:[{url,title,thumbnail_url}], has_next_page}`. Status
codes: 0 unknown, 1 ongoing, 2 completed, 5 cancelled, 6 hiatus.

`http.get` opts are forwarded verbatim to the host (Object.assign), so extensions
can pass these host knobs:
- `headers` — e.g. `{Referer: base+'/'}`.
- `webview_force: true` — route through the offscreen WebView proxy even on a
  clean 200 (for JS-SPA / JS-injected content).
- `webview_settle_ms: N` — CEILING for how long the proxy waits after the page is
  ready (default 1800).
- `webview_ready_js: "<JS boolean expr>"` — proxy returns as soon as this is
  true (e.g. `"document.querySelectorAll('.comic-card').length>0"`); else it
  uses DOM node-count stabilisation, capped by the ceiling.

## Cloudflare / SPA strategy (key architecture)
- CF fingerprint-walls Dio (TLS/JA3) even with a valid `cf_clearance`. Solution:
  the **WebView proxy** (`flutter/lib/data/network/webview_http_client.dart`) —
  a full-size offscreen WebView (behind the opaque app) navigates to the URL
  (passing CF via the Chromium fingerprint), waits for readiness, extracts the
  rendered DOM (`outerHTML`, or `body.innerText` for JSON). `serviceHttp`
  (`flutter/lib/data/source/js/js_runtime.dart`) routes to it on a CF challenge
  OR when `webview_force` is set.
- **SPA sites** (client-rendered, e.g. mgeko) → Dio gets an empty shell, so set
  `webview_force` on every fetch + a `webview_ready_js` for the content.
- Covers on hotlink/CF-walled CDNs can't ride the HTML proxy → a WebView canvas
  fetch (`fetchImageBytes`: park on the cover origin, `Image`→canvas→toDataURL→
  base64). Wired as the `cached_network_image` errorWidget fallback in
  `flutter/lib/presentation/common/source_image.dart`.

## Extension inventory + status
Templates: `_ext_madara.js` (Madara/WordPress cluster), `_ext_mangathemesia.js`
(WPMangaStream cluster), `_ext_natomanga.js` (manganato theme). Clone = copy the
template, change the CONFIG block (BASE/ID/NAME/LANG/MPATH/DIR/AJAX_CHAPTERS).

**✅ Working, device-verified (~14):** natomanga (manganato), mangadex,
manhuaplus, manhwatop, manhuatop, manhuafast (incl. AJAX chapters), rizzfables
(rizz comic), thunderscans, harimanga, toongod, demonicscans (manga demon, full
e2e), allporncomic (titles work; covers blank = cover-CF, has fallback),
**webtoons** (full e2e), **mgeko** (full e2e via SPA force-render).

**🟡 Built, NOT device-verified (3):** kunmanga, manhuaus, manhwaclan (same
Madara template; origins were CF-521-down earlier — re-test when up).

**🔲 SPA cluster — REMAINING (3):** asura (asuracomic.net), hivetoons (hive),
vortexscans (vortex). All CF-walled Next.js (`/series/<slug>` + storage CDN).
Use the **proven mgeko recipe** (below). I was mid-dump on hivetoons when this
handoff was requested.

**🔲 Not built:** viz manga + viz shonen-jump (licensed/DRM pages), tapas
(tapas.io — browse/episodes 302/session-gated), 3hentai (3hentai.net — NOT CF;
`/d/<id>` galleries, NO nhentai JSON API, images `s1.3hentai.net/d<mediaId>/<n>t.jpg`
thumb → `<n>.jpg` full; image logic solved, but listing/details have no og: meta
so titles are hard), readallcomics (NOT CF; unusual `category`-as-series +
`htp-search-result`), read comic online (CF + remote-obfuscated `imageDecryptEval`
pages — hard), aqua manga / arya scans (→brainrotcomics) / manga yy
(dead/unknown — unprobed).

## The PROVEN SPA-cluster recipe (mgeko did this end-to-end)
1. **Dev-dump the rendered DOM** for: the listing page, a series page, the
   chapter-list page, and a reader page (workflow below).
2. Author the extension: every `getHtml` passes `webview_force:true` +
   `webview_settle_ms:12000` + a per-call `webview_ready_js` (listing → the card
   selector; chapters → the chapter-row selector; details/pages → e.g.
   `"document.images.length>0"`).
3. Parse the rendered DOM with the usual regex helpers.
4. Push + device-verify popular/covers/details/chapters/reader.
mgeko reference: cards `a[href^="/manga/"]` + `.comic-card__title`, covers on
`imgsrv4.com`, chapters at `/manga/<slug>/all-chapters/` (`a[href^="/reader/en/"]`
+ `strong.chapter-title`), pages `imgsrv4.com/sv2/comic/<slug>/chapter-N/<n>.jpg`.

### Dev page-source dump workflow (gets rendered DOM for CF/SPA sites)
More ▸ "Dev: page source" (DEV-only tool, `lib/presentation/dev/`). It loads a
URL in a real WebView, **Dump** writes `app_flutter/devdump.html`; pull with
`adb exec-out run-as app.mohyeong.dev cat app_flutter/devdump.html > out.html`.
**UI-automation gotchas (these bit repeatedly):**
- Reach **More from the Library screen**, NOT from a scrolled Sources list (its
  bottom nav isn't at a fixed y → mis-taps). Force-stop+relaunch lands on Library.
- Screen is 1080×2460; resize screenshots to ≤2000px tall before reading them
  (resize to height 1230 → scale ×2.0 for easy mapping).
- Chapter rows: tap the **title text (x≈300)**, NOT x≈970 (that's the ⋮ menu).
  The Start FAB is x≈790, not 950.
- Chapter/detail counts show a small mid-sync number then settle — wait for the
  top-right spinner to clear before trusting a chapter count.
- App **caches details+chapters per manga** — to re-test a chapters change, open
  a manga NOT opened before (or hit Refresh).

## ADB / device workflow
- Wireless ADB, port rotates + drops frequently. Reconnect:
  `adb mdns services | grep _adb-tls-connect` then `adb connect <ip:port>`;
  occasionally needs re-pair (`adb pair <ip:pairport> <code>`).
- Pushes can silently copy STALE `/data/local/tmp` files if the link blips
  mid-push — use a fresh temp name each push and verify with `run-as ... grep`.
- No `sqlite3`/`gh` on device; uiautomator returns the wrong window (the
  offscreen WebView) — drive by screencap + pixel taps. Pull the Drift DB via
  `adb exec-out run-as app.mohyeong.dev cat app_flutter/mihon.sqlite > m.sqlite`
  then query with Python sqlite3.
- Windows `convert` is NOT ImageMagick — resize screenshots with Python PIL.

## PC test harness (verify non-CF extensions WITHOUT the device)
`flutter/.tmp_manifests/test_ext.js` (untracked scratch — recreate if missing):
stubs the host `http` bridge with node's global `fetch`, evals an `_ext_*.js`,
and runs a method against the LIVE site. Only works for non-CF sources.
```
node .tmp_manifests/test_ext.js _ext_webtoons.js popular
node .tmp_manifests/test_ext.js _ext_webtoons.js details <url>
node .tmp_manifests/test_ext.js _ext_webtoons.js chapters <url>
```
webtoons was fully verified this way before the device pass.

## Performance work
**Round 1 — committed + DEVICE-VERIFIED:**
- Condition-based WebView settle (`_awaitContent`: `webview_ready_js` predicate
  OR DOM node-count stabilisation; `webview_settle_ms` ceiling; 250ms poll) —
  replaced the flat 1.8s/8s sleeps.
- `pickCover()` (prefer absolute http candidate; fixes harimanga broken data-src);
  broad Madara series-path filter; cover canvas capped 480px; `maxWidthDiskCache`
  + `ResizeImage` on the WebView cover fallback; `attr()` regex memoised.

**Round 2 — committed, BUILD-verified, DEVICE-VERIFICATION PENDING (do this
first on the new device):**
- serviceHttp: `webview_force` goes WebView-FIRST (skips the wasted Dio shell),
  falls back to Dio if WebView null; 12s success-only idempotent `_respCache`
  (`"method url"`) collapsing the details+chapters double-fetch.
- `fetchImageBytes`: negative-cache failed covers (2min) + coalesce in-flight
  identical URLs.
- mgeko details/pages got `webview_ready_js`.
- **VERIFY:** open several sources (a non-CF one e.g. webtoons, a CF Madara, a
  SPA e.g. mgeko) — confirm popular/details/chapters/reader all still load and
  feel faster; confirm a manual "Refresh from source" still re-fetches (not
  served stale from the 12s cache).

**Deferred consensus backlog (both Opus reviewers ranked the first as #1):**
1. **The ~50s first-grid-load on fully-walled sources** — covers go through
   `cached_network_image` (own http client, no timeout cap) before the WebView
   fallback, and all covers serialise through the ONE WebView `_lock`. Fixes:
   (a) per-source "covers walled → skip CNI, use `_WebViewImageProvider`
   directly" flag (thread a manifest bool through `source_image.dart` like
   `installedSourceImageHeadersProvider` is threaded); (b) **batch same-origin
   covers in ONE JS pass** over the already-parked listing page (fan out N ids
   over the existing `CFImg` channel) — biggest single win.
2. `chapter_repository.dart` `syncChaptersWithSource` (~:213) inserts new
   chapters one-by-one — batch insertAll + re-query ids (CORRECTNESS-sensitive:
   `added` feeds Updates/auto-download; preserve the `markDuplicateAsRead`
   exclusion).
3. `manga_details_screen.dart` `_ChaptersSection` re-filters/sorts/interleaves
   the whole list on every download-progress `setState` tick — memoise the
   render list (key on chapters identity + filters/sort/excluded/downloaded), or
   per-tile progress notifiers.

## Build / verify commands
```
cd flutter
flutter analyze lib/            # must stay clean
flutter test                    # 18 trivial tests, keep green
flutter build apk --debug
node --check _ext_<id>.js        # JS syntax-check every extension edit
```

## Hard constraints
- **Do NOT run `dart format`** — it churns ~800 lines of
  `manga_details_screen.dart`; the repo is not format-clean.
- Strict 1:1 parity with Mihon; honest wiring (no dead switches).
- Commit per logical chunk; commit messages end with
  `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`.
- The "Dev: page source" tool + the side-loaded `_ext_*.js` are dev artifacts;
  decide a shippable bundling location before release (currently uncommitted on
  device, committed in-repo as `flutter/_ext_*.js`).

## Immediate next steps (priority order)
1. Device-verify the Round-2 perf changes (above) on the new device.
2. Finish the **SPA cluster**: hivetoons → vortexscans → asura (proven recipe).
3. Deferred perf #1 (the ~50s grid: skip-CNI flag + batch covers).
4. Optional one-offs: webtoons-style API sources, 3hentai (image logic ready),
   readallcomics; skip viz (DRM) / tapas (session) unless needed.
