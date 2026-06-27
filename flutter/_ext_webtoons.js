// WEBTOONS (webtoons.com) extension for Mohyeong's JS runtime.
// Not Cloudflare-walled. Listing/details are scraped HTML; the chapter list
// comes from the mobile JSON episode API. Authored against live HTML + the
// real /api/v1 response (Tower of God title_no=95). Ported from the Keiyoushi
// Webtoons source. Contract: register `__extension`. Globals: http.get, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://www.webtoons.com';
  var MOBILE = 'https://m.webtoons.com';
  var LANG = 'en';      // language code in the URL paths + API
  var ID = 'webtoons';
  var NAME = 'WEBTOONS';
  // =========================================================================

  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  var _attrRe = {};
  function attr(tag, name) {
    if (!tag) return null;
    var re = _attrRe[name];
    if (!re) {
      re = _attrRe[name] = [
        new RegExp(name + '\\s*=\\s*"([^"]*)"'),
        new RegExp(name + "\\s*=\\s*'([^']*)'"),
      ];
    }
    var m = re[0].exec(tag);
    if (m) return m[1];
    m = re[1].exec(tag);
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
  function abs(url, baseUrl) {
    baseUrl = baseUrl || BASE;
    if (!url) return url;
    if (url.indexOf('//') === 0) return 'https:' + url;
    if (url.indexOf('http') === 0) return url;
    if (url.charAt(0) === '/') return baseUrl + url;
    return baseUrl + '/' + url;
  }
  function getText(url) {
    return http.get(url, { headers: { Referer: BASE + '/', 'User-Agent': UA } }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return r.body || '';
    });
  }
  function qparam(url, key) {
    var m = new RegExp('[?&]' + key + '=([^&]+)').exec(url || '');
    return m ? decodeURIComponent(m[1]) : null;
  }

  // --- listing -------------------------------------------------------------
  // Ranking/search cards: ul.webtoon_list li > a[href*=title_no] with the
  // title in .subj/.title and an <img> cover. The card anchor IS the series
  // list URL (carries title_no), which we use as the manga url.
  function parseList(html) {
    var out = [];
    var seen = {};
    var re = /<a\s+[^>]*href="([^"]*title_no=\d+[^"]*)"[^>]*>([\s\S]*?)<\/a>/g, m;
    while ((m = re.exec(html)) !== null) {
      var url = decode(m[1]);
      var no = qparam(url, 'title_no');
      if (!no || seen[no]) continue;
      seen[no] = true;
      var inner = m[2];
      var tM = /class="[^"]*(?:subj|title)[^"]*"[^>]*>([\s\S]*?)<\//.exec(inner);
      var title = tM ? stripTags(tM[1]) : '';
      var imgM = /<img\b[^>]*>/.exec(inner);
      var cover = imgM ? (attr(imgM[0], 'src') || attr(imgM[0], 'data-url')) : null;
      if (!title) continue;
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  function popular(page) {
    return getText(BASE + '/' + LANG + '/ranking/popular').then(function (html) {
      return { mangas: parseList(html), has_next_page: false };
    });
  }
  function latest(page) {
    return getText(BASE + '/' + LANG + '/ranking/trending').then(function (html) {
      return { mangas: parseList(html), has_next_page: false };
    });
  }
  function search(query, page) {
    var url = BASE + '/' + LANG + '/search?keyword=' + encodeURIComponent(query || '') + '&page=' + page;
    return getText(url).then(function (html) {
      var mangas = parseList(html);
      return { mangas: mangas, has_next_page: mangas.length > 0 };
    });
  }

  // --- details -------------------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toUpperCase();
    if (s.indexOf('COMPLETED') >= 0 || s.indexOf('END') >= 0) return 2;
    if (s.indexOf('UP') >= 0 || s.indexOf('ONGOING') >= 0) return 1;
    if (s.indexOf('HIATUS') >= 0 || s.indexOf('REST') >= 0) return 6;
    return 1; // webtoons titles are ongoing by default
  }
  function meta(html, prop) {
    var m = new RegExp('<meta[^>]+property="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
    return m ? m[1] : null;
  }
  function details(manga) {
    return getText(abs(manga.url)).then(function (html) {
      var tM = /<(?:h1|h3)[^>]*class="[^"]*subj[^"]*"[^>]*>([\s\S]*?)<\/(?:h1|h3)>/.exec(html);
      var title = tM ? stripTags(tM[1]) : (meta(html, 'og:title') || manga.title || '');

      var author = null;
      var auM = /class="[^"]*author(?:_area)?[^"]*"[^>]*>([\s\S]*?)<\//.exec(html);
      if (auM) author = stripTags(auM[1]);

      var description = null;
      var dM = /<p[^>]*class="[^"]*summary[^"]*"[^>]*>([\s\S]*?)<\/p>/.exec(html);
      if (dM) description = decode(stripTags(dM[1]));
      else description = meta(html, 'og:description');

      var genres = [];
      var gre = /class="[^"]*genre[^"]*"[^>]*>([\s\S]*?)<\//g, gm;
      while ((gm = gre.exec(html)) !== null) {
        var g = stripTags(gm[1]); if (g) genres.push(decode(g));
      }

      var status = 0;
      var stM = /class="[^"]*day_info[^"]*"[^>]*>([\s\S]*?)<\//.exec(html);
      if (stM) status = mapStatus(stripTags(stM[1]));

      var cover = meta(html, 'og:image');

      return {
        url: manga.url,
        title: decode(title),
        author: author ? decode(author) : null,
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
  // Mobile JSON API: /api/v1/{webtoon|canvas}/{titleId}/episodes?pageSize=99999
  // → result.episodeList[]{episodeNo, episodeTitle, viewerLink, exposureDateMillis}.
  function chapters(manga) {
    var u = abs(manga.url);
    var titleId = qparam(u, 'title_no') || qparam(u, 'titleNo');
    if (!titleId) return Promise.resolve([]);
    var type = u.indexOf('/canvas/') >= 0 ? 'canvas' : 'webtoon';
    var api = MOBILE + '/api/v1/' + type + '/' + titleId + '/episodes?pageSize=99999';
    return http.get(api, { headers: { Referer: BASE + '/', 'User-Agent': UA } }).then(function (r) {
      if (!r || r.ok === false || r.status < 200 || r.status >= 300) throw new Error('HTTP ' + (r && r.status));
      var data;
      try { data = JSON.parse(r.body || '{}'); } catch (e) { return []; }
      var list = (data.result && data.result.episodeList) || [];
      var out = [];
      for (var i = 0; i < list.length; i++) {
        var ep = list[i];
        if (!ep.viewerLink) continue;
        out.push({
          url: abs(ep.viewerLink),
          name: decode(ep.episodeTitle || ('Episode ' + ep.episodeNo)),
          date_upload: ep.exposureDateMillis || 0,
          chapter_number: typeof ep.episodeNo === 'number' ? ep.episodeNo : -1,
        });
      }
      return out;
    });
  }

  // --- pages ---------------------------------------------------------------
  // Viewer page: div#_imageList > img[data-url] (CDN needs the webtoons Referer).
  function pages(chapter) {
    return getText(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var start = html.indexOf('_imageList');
      var region = start >= 0 ? html.substring(start) : html;
      var re = /<img\b([^>]*)>/g, m;
      while ((m = re.exec(region)) !== null) {
        var src = attr(m[1], 'data-url') || attr(m[1], 'data-src') || attr(m[1], 'src');
        if (!src) continue;
        src = src.replace(/^\s+|\s+$/g, '');
        if (src.indexOf('http') !== 0) continue;
        if (/\/static\/|logo|loading|ad\./i.test(src)) continue;
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
