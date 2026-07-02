// Asura Scans (asuracomic.net → asurascans.com) extension for Mohyeong's JS
// runtime. Astro SSR front end backed by a JSON API, authored against live
// HTML/API:
//   listings/search : https://api.asurascans.com/api/series
//       ?page=N&sort=popular|update  (popular / latest) and &search=<q>
//       → {data:[{slug,title,cover,status,public_url,…}], meta:{total,per_page,
//          has_more}}
//   details : https://api.asurascans.com/api/series/<slug-or-slug-hash>
//       → {series:{title,cover,status,author,artist,genres[],description,…}}
//   chapters: the SSR comic page /comics/<slug>-<hash> lists every chapter
//       inline (<a href="/comics/<slug>-<hash>/chapter/N"> + a relative or
//       "Mon DD, YYYY" date) — the detail API omits chapters.
//   reader  : cdn.asurascans.com/asura-images/chapters/<slug>/<N>/NNN.webp
// public_url already carries the routing hash (…-30e93729), so we build every
// series/chapter URL from what the site itself returns, never a guessed hash.
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://asurascans.com';
  var APIBASE = 'https://api.asurascans.com';
  var ID = 'asura';
  var NAME = 'Asura Scans';
  var LANG = 'en';
  var PER_PAGE = 20;
  // =========================================================================

  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  var ENTITIES = {
    '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#039;': "'",
    '&#39;': "'", '&apos;': "'", '&nbsp;': ' ', '&rsquo;': '’', '&lsquo;': '‘',
    '&hellip;': '…', '&mdash;': '—', '&ndash;': '–', '&#038;': '&',
  };
  function decode(s) {
    if (!s) return s;
    return s.replace(/&[a-z#0-9]+;/gi, function (e) {
      if (ENTITIES[e] != null) return ENTITIES[e];
      var m = /^&#(\d+);$/.exec(e);
      return m ? String.fromCharCode(parseInt(m[1], 10)) : e;
    });
  }
  function stripTags(s) {
    return s ? s.replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ').trim() : s;
  }
  function abs(url) {
    if (!url) return url;
    if (url.indexOf('//') === 0) return 'https:' + url;
    if (url.indexOf('http') === 0) return url;
    if (url.charAt(0) === '/') return BASE + url;
    return BASE + '/' + url;
  }
  function getHtml(url) {
    return http.get(url, { headers: { Referer: BASE + '/' } }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return r.body || '';
    });
  }
  function getJson(url) {
    return getHtml(url).then(function (body) { return JSON.parse(body); });
  }

  // --- listing (JSON API) ---------------------------------------------------
  function mapList(data) {
    var posts = (data && data.data) || [];
    var mangas = [];
    for (var i = 0; i < posts.length; i++) {
      var p = posts[i];
      if (!p || !p.slug) continue;
      // public_url is /comics/<slug>-<hash>; fall back to the plain slug if
      // the API ever omits it (the site tolerates the hashless comic path far
      // less, but it's better than nothing).
      var url = p.public_url ? abs(p.public_url) : (BASE + '/comics/' + p.slug);
      mangas.push({ url: url, title: decode(p.title || p.slug), thumbnail_url: p.cover || null });
    }
    var meta = (data && data.meta) || {};
    var hasNext;
    if (typeof meta.has_more === 'boolean') hasNext = meta.has_more;
    else if (typeof meta.total === 'number') hasNext = mangas.length >= PER_PAGE &&
      curPage * PER_PAGE < meta.total;
    else hasNext = mangas.length >= PER_PAGE;
    return { mangas: mangas, has_next_page: hasNext };
  }
  var curPage = 1;
  function listing(extra, page) {
    curPage = page;
    return getJson(APIBASE + '/api/series?page=' + page + extra).then(mapList);
  }
  function popular(page) { return listing('&sort=popular', page); }
  function latest(page) { return listing('&sort=update', page); }
  function search(query, page) {
    // No &sort — let the API's default relevance ranking lead (forcing
    // sort=popular buries the closest title matches under popular ones).
    return listing('&search=' + encodeURIComponent(query || ''), page);
  }

  // --- details (JSON API) ---------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0 || s.indexOf('paused') >= 0) return 6;
    if (s.indexOf('drop') >= 0 || s.indexOf('cancel') >= 0 || s.indexOf('axed') >= 0) return 5;
    return 0;
  }
  // The comic path segment (<slug>-<hash>) is what /api/series/<x> keys on.
  function seriesSeg(url) {
    var m = /\/comics\/([^\/?#]+)/.exec(url);
    return m ? m[1] : null;
  }
  function details(manga) {
    var seg = seriesSeg(manga.url);
    if (!seg) throw new Error('cannot derive comic slug from ' + manga.url);
    return getJson(APIBASE + '/api/series/' + seg).then(function (data) {
      var s = (data && data.series) || {};
      var genres = [];
      var gs = s.genres || [];
      for (var i = 0; i < gs.length; i++) if (gs[i] && gs[i].name) genres.push(gs[i].name);
      var desc = s.description ? decode(stripTags(s.description)) : null;
      return {
        url: manga.url,
        title: decode(s.title || manga.title || ''),
        author: s.author || null,
        artist: s.artist || null,
        description: desc,
        genre: genres.length ? genres.join(', ') : null,
        status: mapStatus(s.status),
        thumbnail_url: s.cover || manga.thumbnail_url || null,
        initialized: true,
      };
    });
  }

  // --- chapters (scrape the SSR comic page) --------------------------------
  function parseDate(text) {
    if (!text) return 0;
    var m = /(\d+)\s*(second|minute|hour|day|week|month|year)s?\s*ago/i.exec(text);
    if (m) {
      var n = parseInt(m[1], 10);
      var ms = { second: 1e3, minute: 6e4, hour: 36e5, day: 864e5, week: 6048e5,
        month: 2629746e3, year: 31556952e3 }[m[2].toLowerCase()] || 0;
      return Date.now() - n * ms;
    }
    var dm = /[A-Z][a-z]{2,8}\.?\s+\d{1,2},?\s+\d{4}/.exec(text);
    if (dm) { var p = Date.parse(dm[0]); if (!isNaN(p)) return p; }
    return 0;
  }
  function chapters(manga) {
    var seg = seriesSeg(manga.url);
    if (!seg) throw new Error('cannot derive comic slug from ' + manga.url);
    return getHtml(abs(manga.url)).then(function (html) {
      var out = [];
      var seen = {};
      var re = new RegExp(
        '<a\\b[^>]*href="((?:https?://[^"]*)?/comics/' +
        seg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') +
        '/chapter/([0-9.]+))"[^>]*>([\\s\\S]{0,800}?)</a>', 'g');
      var m;
      while ((m = re.exec(html)) !== null) {
        var url = abs(m[1]);
        if (seen[url]) {
          // Nav buttons ("First/Latest Chapter") duplicate a real row's URL
          // but carry no date — let a later dated occurrence fill it in.
          continue;
        }
        var num = parseFloat(m[2]);
        var inner = m[3];
        // The chapter label lives in the first non-date span; fall back to the
        // number from the URL (drops the "First/Latest Chapter" button text and
        // the split "Chapter <!-- -->N" comment).
        var name = 'Chapter ' + (isNaN(num) ? m[2] : num);
        var nm = /<span[^>]*font-medium[^>]*>([\s\S]*?)<\/span>/.exec(inner);
        if (nm) {
          var label = stripTags(nm[1]);
          if (/^chapter\b/i.test(label) && !/^(first|latest)\b/i.test(label)) name = decode(label);
        }
        seen[url] = true;
        out.push({ url: url, name: name, date_upload: parseDate(inner), chapter_number: isNaN(num) ? -1 : num });
      }
      out.sort(function (a, b) { return b.chapter_number - a.chapter_number; });
      return out;
    });
  }

  // --- pages ----------------------------------------------------------------
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var re = /<img\b[^>]*\bsrc="([^"]+)"/g, m;
      while ((m = re.exec(html)) !== null) {
        var src = m[1].replace(/^\s+|\s+$/g, '');
        if (src.indexOf('/asura-images/chapters/') < 0) continue;
        if (seen[src]) continue; seen[src] = true;
        out.push({ index: idx++, url: src, image_url: src,
          headers: { Referer: BASE + '/', 'User-Agent': UA } });
      }
      return out;
    });
  }

  function chapterUrl(chapter) { return abs(chapter.url); }

  __extension = {
    manifest: { id: ID, name: NAME, lang: LANG, base_url: BASE, version_code: 1, supports_latest: true },
    popular: popular, latest: latest, search: search,
    details: details, chapters: chapters, pages: pages, chapterUrl: chapterUrl,
  };
})();
