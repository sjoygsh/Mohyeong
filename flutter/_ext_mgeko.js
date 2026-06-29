// MangaGeko (mgeko.cc) extension for Mohyeong's JS runtime.
// Custom theme (not Madara/MangaThemesia), authored against live HTML:
//   browse  : /browse-comics/?results=N&filter=Views|Updated  (card: a[/manga/])
//   series  : /manga/<slug>/            (og: meta for title/cover/description)
//   chapters: /manga/<slug>/all-chapters/  (a[/reader/] > strong + relative date)
//   reader  : imgs on the imgsrv4 CDN  (/comic/<slug>/chapter-N/<i>.webp)
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://www.mgeko.cc';
  var ID = 'mgeko';
  var NAME = 'MangaGeko';
  var LANG = 'en';
  // =========================================================================

  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  function attr(tag, name) {
    if (!tag) return null;
    var m = new RegExp(name + '\\s*=\\s*"([^"]*)"').exec(tag);
    if (m) return m[1];
    m = new RegExp(name + "\\s*=\\s*'([^']*)'").exec(tag);
    return m ? m[1] : null;
  }
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
    return s ? s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() : s;
  }
  function abs(url) {
    if (!url) return url;
    if (url.indexOf('//') === 0) return 'https:' + url;
    if (url.indexOf('http') === 0) return url;
    if (url.charAt(0) === '/') return BASE + url;
    return BASE + '/' + url;
  }
  // mgeko.cc is a client-rendered SPA: a plain Dio GET returns an empty shell
  // (only og: meta is server-rendered). So every fetch FORCES the WebView proxy
  // to run the page JS, and passes a readiness predicate so it returns as soon
  // as the expected content has rendered (capped by webview_settle_ms).
  function getHtml(url, readyJs) {
    var opts = { headers: { Referer: BASE + '/' }, webview_force: true, webview_settle_ms: 12000 };
    if (readyJs) opts.webview_ready_js = readyJs;
    return http.get(url, opts).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return r.body || '';
    });
  }
  function meta(html, prop) {
    var m = new RegExp('<meta[^>]+property="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
    if (m) return m[1];
    m = new RegExp('<meta[^>]+content="([^"]*)"[^>]+property="' + prop + '"', 'i').exec(html);
    return m ? m[1] : null;
  }

  // --- listing -------------------------------------------------------------
  // Cards are <a href="/manga/<slug>/"> wrapping <img> + <h4>title</h4>.
  // Covers lazy-load: real URL in data-src, placeholder.gif in src.
  function parseList(html) {
    var out = [];
    var seen = {};
    var re = /<a\s+[^>]*href="((?:https?:\/\/[^"]*)?\/manga\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/g, m;
    while ((m = re.exec(html)) !== null) {
      var url = m[1];
      var inner = m[2];
      if (/\/all-chapters\/?$/.test(url)) continue;
      if (seen[url]) continue;
      seen[url] = true;
      var imgM = /<img\b[^>]*>/.exec(inner);
      var imgTag = imgM ? imgM[0] : null;
      var cover = attr(imgTag, 'data-src') || attr(imgTag, 'data-lazy-src') || attr(imgTag, 'src');
      if (cover && /placeholder|blank\.gif|lazy/i.test(cover)) {
        cover = attr(imgTag, 'data-src') || attr(imgTag, 'data-lazy-src');
      }
      var title = null;
      var hM = /<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/.exec(inner);
      if (hM) title = stripTags(hM[1]);
      if (!title && imgTag) title = attr(imgTag, 'alt');
      if (!title) title = attr(m[0], 'title') || '';
      out.push({ url: abs(url), title: decode(title || ''), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  function browse(filter, page) {
    var ready = "document.querySelectorAll('.comic-card').length>0";
    return getHtml(BASE + '/browse-comics/?results=' + page + '&filter=' + filter, ready).then(function (html) {
      var mangas = parseList(html);
      return { mangas: mangas, has_next_page: mangas.length > 0 };
    });
  }
  function popular(page) { return browse('Views', page); }
  function latest(page) { return browse('Updated', page); }
  function search(query, page) {
    var url = BASE + '/search/?search=' + encodeURIComponent(query || '');
    return getHtml(url, "document.querySelectorAll('.comic-card').length>0").then(function (html) {
      // Search is a single result page; page>1 has nothing more.
      return { mangas: page > 1 ? [] : parseList(html), has_next_page: false };
    });
  }

  // --- details -------------------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0 || s.indexOf('paused') >= 0) return 6;
    if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
    return 0;
  }
  function details(manga) {
    return getHtml(abs(manga.url), "document.images.length>0").then(function (html) {
      var title = meta(html, 'og:title');
      // og:title is decorated, e.g. "[Manga]: Manga <Title> Read" — strip it.
      if (title) {
        title = decode(title)
          .replace(/^\s*\[manga\]\s*:?\s*/i, '')
          .replace(/^\s*manga\s+/i, '')
          .replace(/\s+read\s*$/i, '')
          .replace(/\s*[-|–]\s*(?:mgeko|manga\s*geko).*$/i, '')
          .trim();
      }
      if (!title) {
        var h1 = /<h1[^>]*>([\s\S]*?)<\/h1>/.exec(html);
        title = h1 ? stripTags(h1[1]) : (manga.title || '');
      }
      var cover = meta(html, 'og:image');
      if (!cover) {
        var cM = /<img\b[^>]*src="([^"]*(?:manga_covers|imgsrv)[^"]*)"/.exec(html);
        cover = cM ? cM[1] : null;
      }
      var description = meta(html, 'og:description');
      if (description) description = decode(description);

      var author = null;
      var auM = /Authors?[^A-Za-z0-9<]{0,12}<a[^>]*>([^<]+)<\/a>/i.exec(html) ||
        /Authors?\s*:?\s*<\/[^>]+>\s*([^<\n]{1,60})/i.exec(html) ||
        /Authors?\s*:\s*([^<\n]{1,60})/i.exec(html);
      if (auM) {
        var au = decode(stripTags(auM[1]).trim());
        if (au && au.toLowerCase() !== 'updating' && au !== '-' && au.toLowerCase() !== 'author') author = au;
      }

      var status = 0;
      var stM = /Status[^A-Za-z0-9<]{0,16}(?:<[^>]*>\s*)?(Ongoing|Completed|Finished|Hiatus|Dropped|Cancel\w*|Paused)/i.exec(html);
      if (stM) status = mapStatus(stM[1]);

      var genres = [];
      var gSec = /Genres?\s*<\/[^>]+>([\s\S]{0,600}?)<\/(?:div|ul|td|p)>/i.exec(html) ||
        /class="[^"]*categories[^"]*"[^>]*>([\s\S]{0,600}?)<\/(?:div|ul)>/i.exec(html);
      if (gSec) {
        var gre = /<a[^>]*>([\s\S]*?)<\/a>/g, gm;
        while ((gm = gre.exec(gSec[1])) !== null) {
          var g = stripTags(gm[1]); if (g) genres.push(decode(g));
        }
      }

      return {
        url: manga.url,
        title: decode(title || ''),
        author: author,
        artist: null,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        status: status,
        thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
        initialized: true,
      };
    });
  }

  // --- chapters ------------------------------------------------------------
  function parseRelativeDate(text) {
    var m = /(\d+)\s*(second|minute|hour|day|week|month|year)/i.exec(text);
    if (!m) return 0;
    var n = parseInt(m[1], 10);
    var unit = m[2].toLowerCase();
    var ms = { second: 1e3, minute: 6e4, hour: 36e5, day: 864e5, week: 6048e5,
      month: 2629746e3, year: 31556952e3 }[unit] || 0;
    return Date.now() - n * ms;
  }
  function chapters(manga) {
    var url = abs(manga.url).replace(/\/+$/, '') + '/all-chapters/';
    return getHtml(url, "document.querySelectorAll('.chapter-title').length>0").then(function (html) {
      var out = [];
      var seen = {};
      var re = /<a\s+[^>]*href="((?:https?:\/\/[^"]*)?\/reader\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/g, m;
      while ((m = re.exec(html)) !== null) {
        var u = m[1];
        if (seen[u]) continue;
        seen[u] = true;
        var inner = m[2];
        var sM = /<strong[^>]*>([\s\S]*?)<\/strong>/.exec(inner);
        var raw = sM ? stripTags(sM[1]) : stripTags(inner);
        var name = raw.replace(/-eng-li\b/ig, '').replace(/\s+/g, ' ').trim();
        if (/^\d/.test(name)) name = 'Chapter ' + name;
        var rest = stripTags(inner.replace(/<strong[\s\S]*?<\/strong>/i, ''));
        var date = parseRelativeDate(rest);
        if (!date) { var p = Date.parse(rest); if (!isNaN(p)) date = p; }
        out.push({ url: abs(u), name: decode(name) || u, date_upload: date, chapter_number: -1 });
      }
      return out;
    });
  }

  // --- pages ---------------------------------------------------------------
  // Reader images sit directly in the document on the imgsrv CDN
  // (/comic/<slug>/chapter-N/<i>.webp). No reader container element.
  function pages(chapter) {
    return getHtml(abs(chapter.url), "document.images.length>2").then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var re = /<img\b([^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        var src = attr(m[1], 'data-src') || attr(m[1], 'src');
        if (!src) continue;
        src = src.replace(/^\s+|\s+$/g, '');
        if (src.indexOf('http') !== 0) continue;
        if (!/\/comic\/|\/sv\d|imgsrv/i.test(src)) continue;
        if (/placeholder|logo|avatar|loading/i.test(src)) continue;
        if (seen[src]) continue; seen[src] = true;
        out.push({ index: idx++, url: src, image_url: src, headers: { Referer: BASE + '/', 'User-Agent': UA } });
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
