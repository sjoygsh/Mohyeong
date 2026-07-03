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

**✅ Working, device-verified (~25):** natomanga (manganato), mangadex,
manhuaplus, manhwatop, manhuatop, rizzfables (rizz comic), thunderscans,
harimanga, toongod, demonicscans (manga demon, full e2e), **manhuaus** (Madara,
875-ch verified), **webtoons** (full e2e), **mgeko** (full e2e via SPA
force-render), **hivetoons**, **vortexscans**, **asura** (SPA cluster, full
e2e), **genztoons** (rebuilt for its relaunch — see note), **3hentai** (doujin
gallery, full e2e), **brainrot** (brainrotcomics; scroll-until-stable chapter
load — see note), **aquareader** (aquamanga relaunch, full e2e),
**tapas** (free-eps-only, full e2e), **allporncomic** (moved to
allporncomics.co, WebView-forced — see 2026-07-03 notes; full e2e ✅).

**🔴 Broken by the SITE, not our code (re-test when the origin is up):**
kunmanga (CF 522 origin-down), manhwaclan (CF 522 origin-down), manhuafast
(CF 502 origin-down; its extension is fine — was device-proven before),
readallcomics (CF 521 origin-down). All confirmed via the Dev-page-source
WebView on 2026-07-02, so it's the origins, not our fetch path.

**🔴 Can't be done (parked with reason):** mangayy (CF interactive
"Just a moment"), read comic online (remote-obfuscated `imageDecryptEval`),
viz (DRM / session-gated — skip per original handoff). aryascans
redirects to brainrotcomics, which IS added, so arya is covered by **brainrot**.
(aquamanga and tapas left this bucket on 2026-07-03 — see below.)

**✅ SPA cluster — DONE (2026-07-02).** All three turned out to be Astro SSR
sites, NOT the CF-walled Next.js the handoff assumed, and none needed the
mgeko force-render recipe — plain Dio fetches work:
- **hivetoons** (hivetoons.org) + **vortexscans** (vortexscans.org) are the
  SAME "toon" platform (config clones). Listings/search via
  `api.<host>/api/query` (orderBy=totalViews popular / updatedAt latest /
  searchTerm=q). Details/pages scraped from the `/series/<slug>` SSR page.
  Chapters come from the page's **Astro hydration island props** (`initialChap`
  array) — the SSR only renders a recent window of `<a>` links, so scraping
  those truncates long series (Vortex showed 21 of 224). `unescapeEntities` +
  `undoAstro` (Astro wraps every value `[0,x]`/`[1,[…]]`) decode the island;
  it carries per-chapter `isAccessible` (skip coin/time-locked), `createdAt`,
  `number`. Covers/pages on `storage.<host>` (open hotlink; large animated GIF
  covers just load slowly — not broken).
- **asura** (asuracomic.net → asurascans.com). Listings/search/details via
  `api.asurascans.com/api/series` (`sort=popular|update`, `search=`,
  `/api/series/<slug>` detail). `public_url` carries the routing hash
  (…-30e93729) so URLs are never guessed. Chapters scraped from the
  `/comics/<slug>-<hash>` SSR page (full list inline; verified 93/93 vs API
  chapter_count). Pages on `cdn.asurascans.com/asura-images/chapters/…`.

**Other 2026-07-02 additions:**
- **genztoons** — the old genztoons.com MangaThemesia clone broke: that domain
  expired and is PARKED (router.parklogic.com). The site relaunched on
  genztoons.org (canonical; genzupdates.com mirrors) on the "Meowing" platform,
  so `_ext_genztoons.js` was rewritten ground-up: catalog is the whole
  `/series/` page (~205 cards, no server pagination/search → search filters
  client-side), `/latest/` for latest, chapter anchors are self-describing
  (`<a href="/chapter/<hash>" title="Chapter 45" d="Nov 13, 2024">`), images on
  `cdn.meowing.org/uploads/<uid>` (eager first page via wp.com proxy + lazy
  `uid=` placeholders). Series status only lives in the bookmark dropdown → left
  unknown. NOTE cold chapter pages can exceed Dio's 30s timeout once (Retry
  works).
- **3hentai** (3hentai.net) — server-rendered doujin gallery, NOT CF, NO JSON
  API. popular=`/`, latest=`/language/english`, search=`/search?q=` (empty q
  404s → popular). Gallery = one chapter; thumbs `s#/d<media>/<n>t.<ext>` → full
  drops the `t`. Titles come from the card `.title` div / gallery h1 (the old
  "no og: meta" worry was moot).
- **brainrot** (brainrotcomics.com; = arya scans redirect) — CF-walled Madara.
  The catch: chapters lazy-load only on scroll and NEVER populate in the normal
  page offscreen. Fix: fetch the classic `?style=list` variant AND, because
  LiteSpeed keeps only visible rows mounted, the `webview_ready_js` scrolls to
  the bottom each poll and waits for the row count to STABILISE before
  extracting (20s ceiling — the occluded/backgrounded WebView is render-
  throttled, so it needs far longer than a foreground tab). This
  scroll-until-stable pattern is reusable for other lazy-load Madara sites.

**✅ 2026-07-03 additions — device-verified (see one 🟡 note at the end):**
- **aquareader** (`_ext_aquareader.js`, NEW) — aquamanga's live successor:
  the site relaunched on aquareader.org (some media still 301s via
  aquareader.net). Madara underneath but with a custom "aqua" skin, so the
  selectors differ from stock: cards `article.aqua-archive-card`, chapter rows
  `a.aqua-ch-item` (name/time spans), genres `a.aqua-series-genre-pill`;
  search still uses stock `c-tabs-item` rows. No CF. Device-verified e2e:
  popular grid + covers, details (genres/status/desc), 319-ch list with dates,
  reader 14 pages.
- **tapas** (`_ext_tapas.js`, NEW) — FREE episodes only, like Mihon's source;
  un-parked from the can't-do bucket. Listings via the open
  `story-api.tapas.io/cosmos/api/v1/landing/{ranking,new}` JSON; search +
  /series/<x>/info are still server-rendered; chapters via the
  `/series/<numericId>/episodes?page=N` XHR JSON; pages = `img.content__img`
  data-src. TRAPS (each cost a debug round):
  (1) `data-is-wait-or-pay`/`data-is-charging` do NOT track anonymous
  readability on "Wait Until Free" series (wop=true on always-free early eps,
  false on sign-in-gated ones) — filter rows by CLASS instead: gated rows
  carry `body__item--opaque`/`js-have-to-sign`, readable rows neither.
  (2) A mobile UA 302s to m.tapas.io — same episode-row + content__img markup,
  but every m. page has a `js-have-to-sign` banner (never use it as a
  page-level lock signal; zero content__img ⇒ locked) and image URLs are
  HTML-escaped in attrs (`&amp;` → decode).
  (3) The cosmos API returns cover paths WITHOUT a file extension and the bare
  path 404s — append `.jpg` (found on-device: grey grid).
  Device-verified e2e: popular grid + covers, details, free-chapter filter
  (3 free eps on a premium series), reader 63 pages. PC: WUF series 5/109
  free (correct), free community series all 661 eps.
- **allporncomic v2 → allporncomics.co** (`_ext_allporncomic.js` reworked) —
  the Turnstile-walled allporncomic.com moved to **allporncomics.co**, which
  WAF-403s every non-browser TLS fingerprint outright (plain block page, NOT a
  solvable challenge — serviceHttp's CF detection never reroutes, and PC
  curl/node can't test it at all). What the new site needed, all found via the
  Dev-page-source dump loop:
  (1) `webview_force:true` (+8s settle) on EVERY getHtml — the WebView's real
  Chrome TLS passes the WAF fine.
  (2) The Madara CPT archive is DISABLED (/porncomic/ AND /comic/?m_orderby=…
  redirect home, no cards); browse lives on shortcode pages: `/popular-comics`
  + `/latest`, paginated `/page/N/` (page 2 verified fresh). Those pages render
  NO pagination links → has_next = (cards ≥ 30). Series live at
  `/comic/<slug>/`.
  (3) post-title holds a language-badge anchor (flag emoji) BEFORE the series
  anchor, and when the DOM is captured before wp-emoji swaps the raw glyph for
  an <img>, the first-anchor text is literally "🇺🇸" → titles were flags.
  Parse the series anchor (`href*=/comic/`) + strip regional-indicator glyphs,
  in parseList AND details (badge-span strip there). NOTE the file has TWO
  list parsers (parseList + parseSearch) — patch the right one.
  (4) The rendered DOM carries tracker pixels INSIDE reading-content
  (mc.yandex.ru/watch) → pages() now drops tracker/ad URLs.
  (5) Reader "No pages."/403 (fixed `a5759b149`, ext v3) was TWO more bugs:
  (a) Dart: the WebView 403-fallback for fingerprint-walled CDNs lived only in
  SourceImage's widget branch — crop-borders/rotate-to-fit/dual-page/precache/
  set-as-cover use the raw provider and got NO fallback (crop was ON → every
  page image 403'd). `_NetworkImageWithWebViewFallback` now backs
  `_backendProvider()`; helps every fingerprint-walled source.
  (b) ext pages(): a cold WebView could burn the whole settle window clearing
  the WAF and snapshot an image-less DOM → silent empty list. Now gated on a
  reading-content-img `webview_ready_js`, retried once with a DIFFERENT settle
  ceiling (settle_ms is in the resp-cache key → retry bypasses the cached bad
  snapshot), and an empty parse THROWS (retryable error, not "No pages.").
  Device-verified e2e incl. cold-start reader: ch306 (20 pp) + ch307 (10 pp).

**🔲 Not built (see the two 🔴 buckets above for why each is parked).**

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

**Round 2 — committed + DEVICE-VERIFIED (2026-07-02):**
- serviceHttp: `webview_force` goes WebView-FIRST (skips the wasted Dio shell),
  falls back to Dio if WebView null; 12s success-only idempotent `_respCache`
  collapsing the details+chapters double-fetch.
- `fetchImageBytes`: negative-cache failed covers (2min) + coalesce in-flight
  identical URLs.
- mgeko details/pages got `webview_ready_js`.
- Verified: webtoons / mgeko / harimanga popular+details+chapters+reader all
  load fine; a manual "Refresh from source" on a cached 0-chapter manga
  correctly re-fetched (78 chapters), so the 12s cache doesn't serve stale.
- **Follow-up fix (2026-07-02):** the `_respCache` key now includes the render
  requirements (`webview_force`/`settle`/`ready_js`), not just `"METHOD url"` —
  an AJAX-chapters Madara `chapters()` (which force-renders) could otherwise be
  served the un-rendered shell snapshot a plain `details()` cached for the same
  URL and parse 0 chapters.

**Deferred consensus backlog:**
1. **The ~50s first-grid-load on fully-walled sources** — ⚠️ NOT CURRENTLY
   REPRODUCIBLE (investigated 2026-07-02). The premise needs a source whose
   LISTING loads but whose cover CDN fingerprint-walls even the Referer+UA that
   `installedSourceImageHeadersProvider` already sends to `cached_network_image`.
   No such live source exists: probed the cover CDNs of every working source
   (zinmanga/harimanga, storage.hivetoon, cdn.asurascans, imgsrv4, natomanga) —
   all return 200 to a plain curl WITH Referer+UA, i.e. hotlink-protected at
   most, not fingerprint-walled, so CNI already handles them. The sources whose
   cover CDNs *are* fingerprint-walled (allporncomic, manhuafast) have their
   LISTING walled too — they 403 the popular page (CF fingerprint wall on the
   HTML, no `webview_force`) before any cover renders. So the real blocker there
   is the listing wall, not cover perf. A skip-CNI flag would have no verifiable
   beneficiary today. Revisit IF/when a listing-working, cover-walled source
   appears, OR after recovering allporncomic/manhuafast listings (their CF looks
   like interactive Turnstile — may be unsolvable via the offscreen WebView;
   manhuafast was also origin-502 flaky on 2026-07-02). Original fix ideas kept
   for reference: (a) per-source "covers walled → skip CNI, use
   `_WebViewImageProvider` directly" manifest flag; (b) batch same-origin covers
   in ONE JS pass over the parked listing page.
2. ✅ DONE 2026-07-02: `syncChaptersWithSource` batched insertAll + id re-query
   (was one INSERT per new chapter; 319-chapter fresh insert device-verified,
   4 unit tests in `test/sync_chapters_test.dart`, added `AppDatabase.forTesting`
   for in-memory DB tests). `added` order / mark-duplicate-read exclusion / read
   preservation / prune-missing all covered.
3. ✅ DONE 2026-07-02: `_ChaptersSection` render list memoised (keyed on
   chapters identity + excluded set + downloaded-filter revision + group/hide/
   manga) so download-progress ticks no longer re-run the whole filter→sort→
   interleave. Device-verified on Get Schooled (254 ch): list identical, a
   chapter download shows live progress + lands on disk.

**All three deferred perf items are now resolved (or, for #1, shown to have no
live repro).** Next perf ideas would need profiling a real slow path first.

## Build / verify commands
```
cd flutter
flutter analyze lib/            # must stay clean
flutter test                    # 22 tests now (added test/sync_chapters_test.dart), keep green
flutter build apk --debug
node --check _ext_<id>.js        # JS syntax-check every extension edit
node .tmp_manifests/test_ext.js _ext_<id>.js <method> [arg]   # PC harness (non-CF)
```

## Hard constraints
- **Do NOT run `dart format`** — it churns ~800 lines of
  `manga_details_screen.dart`; the repo is not format-clean.
- Strict 1:1 parity with Mihon; honest wiring (no dead switches).
- Commit per logical chunk. Trailer = whichever model is actually doing the
  work: this session (2026-07-02) that's `Co-Authored-By: Claude Fable 5
  <noreply@anthropic.com>`. (History: the handoff's Opus 4.6 → Opus 4.8 while
  Fable was unavailable → Fable 5 now.)
- The "Dev: page source" tool + the side-loaded `_ext_*.js` are dev artifacts;
  decide a shippable bundling location before release (currently uncommitted on
  device, committed in-repo as `flutter/_ext_*.js`).

## Immediate next steps (priority order)
1. ✅ DONE 2026-07-02: Round-2 perf device-verified; SPA cluster finished
   (hivetoons/vortexscans/asura). Also re-fixed **harimanga** — its refreshed
   theme moved chapters to a JSON API (`/api/comics/<slug>/chapters?per_page=-1`);
   the old inline `li.wp-manga-chapter` scrape found 0. chapters() now hits that
   API with a page-scrape fallback. (version_code bumped 1→2.)
2. Deferred perf #2 DONE (batch chapter insert). Deferred perf #1 (~50s grid)
   found NOT reproducible — see the backlog note below. **Top open perf item is
   now #3** (`_ChaptersSection` re-filter/sort on every setState tick).
3. Optional one-offs: webtoons-style API sources, 3hentai (image logic ready),
   readallcomics; skip viz (DRM) / tapas (session) unless needed.
4. Retest the 🟡 Madara trio (kunmanga/manhuaus/manhwaclan) when their origins
   are up. Note manhuafast was CF-403/502-flaky during this session, and
   allporncomic/manhuafast LISTINGS are CF-fingerprint-walled (403) — their
   Madara `getHtml` does plain Dio and the bare 403 isn't detected as a CF
   challenge, so no WebView retry fires. Recovering them needs a force-render
   listing path, but their wall looks like interactive Turnstile (may not
   auto-solve offscreen) — probe before investing.

### Dev harness note
`flutter/.tmp_manifests/test_ext.js` (the PC test harness) is untracked scratch
and was NOT on this Mac — it's been recreated (node global-fetch `http` stub;
`node .tmp_manifests/test_ext.js _ext_<id>.js <method> [arg]`). Still untracked
by convention. It only works for non-CF sources — used to author + verify
hivetoons/vortexscans/asura/harimanga before each device pass.
