// Genz Toons extension for Mohyeong's JS runtime.
//
// HISTORY: originally a MangaThemesia clone on genztoons.com. That domain
// expired and is parked (router.parklogic.com); the site relaunched on
// genztoons.org (canonical; genzupdates.com mirrors it) on the "Meowing"
// platform — a completely different, server-rendered theme. Authored against
// the live HTML (2026-07-02):
//   catalog : /series/  — the ENTIRE catalog on one page (~205 cards), no
//             server-side pagination or search (params are ignored), so
//             search() filters the parsed catalog client-side.
//   latest  : /latest/  — same card markup in update order.
//   series  : /series/<slug>/ — h1 title, og:image cover, meta description,
//             /series/?genre= links, Artist block. Chapter anchors are
//             self-describing: <a href="/chapter/<hash>-<hash>/"
//             title="Chapter 45" d="Nov 13, 2024" …>.
//   reader  : first page is an eager <img src="https://iN.wp.com/
//             cdn.meowing.org/uploads/<uid>">; the rest are lazy
//             <img uid="<uid>" class="… myImage"> resolved by page JS to
//             https://cdn.meowing.org/uploads/<uid> (open CDN; serves image
//             bytes as text/plain, which Flutter decodes fine by sniffing).
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://genztoons.org';
  var CDN = 'https://cdn.meowing.org/uploads/';
  var ID = 'genztoons';
  var NAME = 'Genz Toons';
  var LANG = 'en';
  // =========================================================================

  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  function attr(tag, name) {
    if (!tag) return null;
    var m = new RegExp('\\b' + name + '\\s*=\\s*"([^"]*)"').exec(tag);
    if (m) return m[1];
    m = new RegExp('\\b' + name + "\\s*=\\s*'([^']*)'").exec(tag);
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
  function meta(html, sel, prop) {
    var m = new RegExp('<meta[^>]+' + sel + '="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
    if (m) return m[1];
    m = new RegExp('<meta[^>]+content="([^"]*)"[^>]+' + sel + '="' + prop + '"', 'i').exec(html);
    return m ? m[1] : null;
  }

  // --- listing ---------------------------------------------------------------
  // Cards: <a href="/series/<slug>/" … title="<Title>"> followed (within the
  // card div) by background-image:url(https://wsrv.nl/?url=cdn.meowing.org/
  // uploads/<hash>&w=600). Cover = the CDN file directly.
  function parseCards(html) {
    var out = [];
    var seen = {};
    var re = /<a\b([^>]*href="(\/series\/[^"?#]+)"[^>]*)>/g, m;
    while ((m = re.exec(html)) !== null) {
      var url = m[2];
      if (seen[url]) continue;
      var title = attr(m[1], 'title') || attr(m[1], 'alt');
      if (!title) continue; // nav / non-card links carry no title attr
      seen[url] = true;
      var tail = html.substring(m.index, m.index + 800);
      var cM = /cdn\.meowing\.org\/uploads\/([A-Za-z0-9]+)/.exec(tail);
      out.push({
        url: abs(url),
        title: decode(title),
        thumbnail_url: cM ? CDN + cM[1] : null,
      });
    }
    return out;
  }
  function popular(page) {
    if (page > 1) return Promise.resolve({ mangas: [], has_next_page: false });
    return getHtml(BASE + '/series/').then(function (html) {
      return { mangas: parseCards(html), has_next_page: false };
    });
  }
  function latest(page) {
    if (page > 1) return Promise.resolve({ mangas: [], has_next_page: false });
    return getHtml(BASE + '/latest/').then(function (html) {
      return { mangas: parseCards(html), has_next_page: false };
    });
  }
  function search(query, page) {
    if (page > 1) return Promise.resolve({ mangas: [], has_next_page: false });
    var q = (query || '').toLowerCase();
    return getHtml(BASE + '/series/').then(function (html) {
      var all = parseCards(html);
      var out = [];
      for (var i = 0; i < all.length; i++) {
        if (all[i].title.toLowerCase().indexOf(q) >= 0) out.push(all[i]);
      }
      return { mangas: out, has_next_page: false };
    });
  }

  // --- details ---------------------------------------------------------------
  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var h1 = /<h1[^>]*>([\s\S]*?)<\/h1>/.exec(html);
      var title = h1 ? stripTags(h1[1]) : (manga.title || '');

      var description = meta(html, 'name', 'description');
      if (description) description = decode(description);

      var cover = meta(html, 'property', 'og:image');
      var cM = cover && /cdn\.meowing\.org\/uploads\/([A-Za-z0-9]+)/.exec(cover);
      if (cM) cover = CDN + cM[1];

      var genres = [];
      var gre = /href="\/series\/\?genre=([a-z0-9-]+)"/g, gm;
      while ((gm = gre.exec(html)) !== null) {
        var g = gm[1].replace(/-/g, ' ');
        g = g.charAt(0).toUpperCase() + g.slice(1);
        if (genres.indexOf(g) < 0) genres.push(g);
      }

      var artist = null;
      var aM = /Artist<\/span>[\s\S]{0,400}?rounded-lg w-fit">\s*([^<]{1,60}?)\s*</.exec(html);
      if (aM) artist = decode(aM[1].trim());

      return {
        url: manga.url,
        title: decode(title || ''),
        author: null,
        artist: artist,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        // The page only renders status words inside the user-bookmark
        // dropdown (every option listed), so the series' own status isn't
        // scrapable from the HTML.
        status: 0,
        thumbnail_url: cover || manga.thumbnail_url || null,
        initialized: true,
      };
    });
  }

  // --- chapters ---------------------------------------------------------------
  // Anchors are self-describing:
  //   <a … href="/chapter/<hash>-<hash>/" title="Chapter 45" d="Nov 13, 2024">
  function chapters(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var out = [];
      var seen = {};
      var re = /<a\b([^>]*href="(\/chapter\/[^"?#]+)"[^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        var url = abs(m[2]);
        if (seen[url]) continue;
        seen[url] = true;
        var tag = m[1];
        var name = attr(tag, 'title') || attr(tag, 'alt') || 'Chapter';
        var date = 0;
        var d = attr(tag, 'd');
        if (d) { var p = Date.parse(d); if (!isNaN(p)) date = p; }
        var nM = /([0-9]+(?:\.[0-9]+)?)/.exec(name);
        out.push({
          url: url,
          name: decode(name),
          date_upload: date,
          chapter_number: nM ? parseFloat(nM[1]) : -1,
        });
      }
      out.sort(function (a, b) { return b.chapter_number - a.chapter_number; });
      return out;
    });
  }

  // --- pages ------------------------------------------------------------------
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var urls = [];
      // First page renders eagerly through the wp.com image proxy.
      var eM = /<img\b[^>]*src="https:\/\/i\d\.wp\.com\/cdn\.meowing\.org\/uploads\/([A-Za-z0-9]+)"[^>]*>/.exec(html);
      if (eM) urls.push(CDN + eM[1]);
      // The rest are lazy placeholders carrying the CDN uid.
      var re = /<img\b([^>]*\bclass="[^"]*myImage[^"]*"[^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        var uid = attr(m[1], 'uid');
        if (uid) urls.push(CDN + uid);
      }
      var out = [];
      var seen = {};
      for (var i = 0; i < urls.length; i++) {
        if (seen[urls[i]]) continue;
        seen[urls[i]] = true;
        out.push({
          index: out.length,
          url: urls[i],
          image_url: urls[i],
          headers: { Referer: BASE + '/', 'User-Agent': UA },
        });
      }
      return out;
    });
  }

  function chapterUrl(chapter) { return abs(chapter.url); }

  __extension = {
    manifest: { id: ID, name: NAME, lang: LANG, base_url: BASE, version_code: 2, supports_latest: true },
    popular: popular, latest: latest, search: search,
    details: details, chapters: chapters, pages: pages, chapterUrl: chapterUrl,
  };
})();
