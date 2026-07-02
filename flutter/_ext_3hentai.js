// 3Hentai (3hentai.net) extension for Mohyeong's JS runtime.
// nhentai-style doujin gallery site, server-rendered, NOT Cloudflare-walled.
// There is NO JSON API (unlike nhentai) — everything scrapes HTML. Authored
// against live pages (2026-07-02):
//   popular : /?page=N — the paginated "Popular Hentai at the moment" feed.
//   latest  : /language/english?page=N — recent English uploads (the whole
//             site is multi-language; this mirrors the usual nhentai-clone
//             "language:english" browse).
//   search  : /search?q=<q>&page=N (empty q 404s, so blank searches map to
//             the popular feed).
//   gallery : /d/<id> — h1 title, card thumbs on s1.3hentai.net/d<mediaId>/,
//             "<N> pages" text, tag/artist/group links, <time datetime>.
//   images  : per-page thumbs are s#.3hentai.net/d<mediaId>/<n>t.<ext>; the
//             full image drops the t → <n>.<ext>. Cover is thumb.jpg.
// A gallery is a single read: details reports COMPLETED and chapters()
// returns one chapter (the gallery itself), like Mihon's nhentai source.
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://3hentai.net';
  var ID = '3hentai';
  var NAME = '3Hentai';
  var LANG = 'en';
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
    return s ? s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() : s;
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

  // --- listing ---------------------------------------------------------------
  // Card: <a href="https://3hentai.net/d/<id>" class="cover">
  //         <img class="lazy" data-src="https://s1.3hentai.net/d<m>/thumb.jpg">
  //         <div class="title …">TITLE</div>
  function parseCards(html) {
    var out = [];
    var seen = {};
    var re = /<a\s+href="(https:\/\/3hentai\.net\/d\/\d+)"[^>]*class="cover"[^>]*>([\s\S]*?)<\/a>/g, m;
    while ((m = re.exec(html)) !== null) {
      var url = m[1];
      if (seen[url]) continue;
      seen[url] = true;
      var inner = m[2];
      var tM = /class="title[^"]*"[^>]*>([\s\S]*?)<\/div>/.exec(inner);
      var cM = /data-src="([^"]+)"/.exec(inner) || /<img[^>]*src="([^"]+)"/.exec(inner);
      out.push({
        url: url,
        title: tM ? decode(stripTags(tM[1])) : url,
        thumbnail_url: cM ? cM[1] : null,
      });
    }
    return out;
  }
  function listing(path) {
    return getHtml(path).then(function (html) {
      var mangas = parseCards(html);
      return { mangas: mangas, has_next_page: mangas.length > 0 };
    });
  }
  function popular(page) { return listing(BASE + '/?page=' + page); }
  function latest(page) { return listing(BASE + '/language/english?page=' + page); }
  function search(query, page) {
    var q = (query || '').trim();
    if (!q) return popular(page); // empty q 404s on /search
    return listing(BASE + '/search?q=' + encodeURIComponent(q) + '&page=' + page);
  }

  // --- details ---------------------------------------------------------------
  function collectLinks(html, kind) {
    var out = [];
    var re = new RegExp('href="https://3hentai\\.net/' + kind + '/[^"]+"[^>]*>([\\s\\S]*?)</a>', 'g');
    var m;
    while ((m = re.exec(html)) !== null) {
      // Tag pills embed a count badge; the name is the text before it.
      var t = decode(stripTags(m[1])).replace(/\s*\d+[KM]?$/, '').trim();
      if (t && out.indexOf(t) < 0) out.push(t);
    }
    return out;
  }
  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var h1 = /<h1[^>]*>([\s\S]*?)<\/h1>/.exec(html);
      var title = h1 ? decode(stripTags(h1[1])) : (manga.title || '');

      var cover = null;
      var mM = /(https:\/\/s\d\.3hentai\.net\/d\d+)\//.exec(html);
      if (mM) cover = mM[1] + '/thumb.jpg';

      var tags = collectLinks(html, 'tags');
      var artists = collectLinks(html, 'artists');
      var groups = collectLinks(html, 'groups');

      var pM = /(\d+)\s*pages/i.exec(html);

      return {
        url: manga.url,
        title: title,
        author: groups.length ? groups.join(', ') : null,
        artist: artists.length ? artists.join(', ') : null,
        description: pM ? pM[1] + ' pages' : null,
        genre: tags.length ? tags.join(', ') : null,
        status: 2, // a gallery is a finished one-shot
        thumbnail_url: cover || manga.thumbnail_url || null,
        initialized: true,
      };
    });
  }

  // --- chapters (one gallery == one chapter) ----------------------------------
  function chapters(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var date = 0;
      var dM = /<time[^>]*datetime="([^"]+)"/.exec(html);
      if (dM) { var p = Date.parse(dM[1]); if (!isNaN(p)) date = p; }
      return [{
        url: abs(manga.url),
        name: 'Chapter',
        date_upload: date,
        chapter_number: 1,
      }];
    });
  }

  // --- pages ------------------------------------------------------------------
  // Per-page thumbs are <mediaDir>/<n>t.<ext>; the full image is <n>.<ext> on
  // the same server. Extensions vary per page (jpg/png/webp), so read each
  // thumb's own extension rather than assuming.
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var re = /(https:\/\/s\d\.3hentai\.net\/d\d+)\/(\d+)t\.(jpg|jpeg|png|webp|gif)/g, m;
      while ((m = re.exec(html)) !== null) {
        var full = m[1] + '/' + m[2] + '.' + m[3];
        if (seen[full]) continue;
        seen[full] = true;
        out.push({
          index: out.length,
          url: full,
          image_url: full,
          headers: { Referer: BASE + '/', 'User-Agent': UA },
        });
      }
      // Page order: the gallery lists thumbs 1..N in DOM order, but be safe.
      out.sort(function (a, b) {
        var na = parseInt(/\/(\d+)\.\w+$/.exec(a.url)[1], 10);
        var nb = parseInt(/\/(\d+)\.\w+$/.exec(b.url)[1], 10);
        return na - nb;
      });
      for (var i = 0; i < out.length; i++) out[i].index = i;
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
