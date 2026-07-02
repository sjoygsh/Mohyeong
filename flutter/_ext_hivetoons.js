// Hive Toons (hivetoons.org) extension for Mohyeong's JS runtime.
// Astro SSR site (replatformed from the old Next.js build) + its own JSON API,
// authored against live HTML/API:
//   listings: https://api.hivetoons.org/api/query?perPage=N&page=N
//             (&orderBy=totalViews popular / updatedAt latest / searchTerm=q)
//             → {posts:[{slug,postTitle,featuredImage,seriesStatus,genres,…}],
//                totalCount}
//   series  : /series/<slug>  (SSR: h1 title, og:image, Status block, chapter
//             rows <a href="/series/<slug>/chapter-N"> with <time dateTime>;
//             genres live in an astro-island's entity-escaped props JSON)
//   reader  : /series/<slug>/chapter-N — page images inline on
//             storage.hivetoon.com/…/upload/series/<slug>/…  (no hotlink wall)
// Newest chapters are coin-locked (timed paywall): their series-page row has a
// bg-black/50 overlay and their reader page has no images — skip them.
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://hivetoons.org';
  var API = 'https://api.hivetoons.org/api/query';
  var ID = 'hivetoons';
  var NAME = 'Hive Toons';
  var LANG = 'en';
  var PER_PAGE = 18;
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
  function getJson(url) {
    return getHtml(url).then(function (body) { return JSON.parse(body); });
  }
  function meta(html, sel, prop) {
    var m = new RegExp('<meta[^>]+' + sel + '="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
    if (m) return m[1];
    m = new RegExp('<meta[^>]+content="([^"]*)"[^>]+' + sel + '="' + prop + '"', 'i').exec(html);
    return m ? m[1] : null;
  }

  // --- listing (all via the JSON query API) --------------------------------
  function listing(params, page) {
    var url = API + '?perPage=' + PER_PAGE + '&page=' + page + params;
    return getJson(url).then(function (data) {
      var posts = (data && data.posts) || [];
      var mangas = [];
      for (var i = 0; i < posts.length; i++) {
        var p = posts[i];
        if (!p || !p.slug) continue;
        mangas.push({
          url: BASE + '/series/' + p.slug,
          title: p.postTitle || p.slug,
          thumbnail_url: p.featuredImage || null,
        });
      }
      var total = data && data.totalCount;
      var hasNext = typeof total === 'number'
        ? page * PER_PAGE < total
        : mangas.length >= PER_PAGE;
      return { mangas: mangas, has_next_page: hasNext };
    });
  }
  function popular(page) { return listing('&orderBy=totalViews', page); }
  function latest(page) { return listing('&orderBy=updatedAt', page); }
  function search(query, page) {
    return listing('&searchTerm=' + encodeURIComponent(query || ''), page);
  }

  // --- details --------------------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0 || s.indexOf('paused') >= 0) return 6;
    if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
    return 0;
  }
  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var h1 = /<h1[^>]*>([^<]+)<\/h1>/.exec(html);
      var title = h1 ? stripTags(h1[1]) : (manga.title || '');

      var description = meta(html, 'name', 'description') ||
        meta(html, 'property', 'og:description');
      if (description) description = decode(stripTags(description));

      var status = 0;
      var stM = /Status<\/h1>[\s\S]{0,300}?>\s*(ONGOING|COMPLETED|FINISHED|HIATUS|PAUSED|DROPPED|CANCEL\w*)\s*</i.exec(html);
      if (stM) status = mapStatus(stM[1]);

      // Genres are serialized in an astro-island's entity-escaped props JSON:
      //   genres&quot;:[1,[[0,{…name&quot;:[0,&quot;Drama&quot;]…
      var genres = [];
      var gBlock = /genres&quot;:\[1,\[([\s\S]{0,3000}?)\]\]/.exec(html);
      if (gBlock) {
        var gre = /name&quot;:\[0,&quot;([^&]+)&quot;/g, gm;
        while ((gm = gre.exec(gBlock[1])) !== null) {
          if (genres.indexOf(gm[1]) < 0) genres.push(gm[1]);
        }
      }

      var cover = meta(html, 'property', 'og:image');

      return {
        url: manga.url,
        title: decode(title || ''),
        author: null,
        artist: null,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        status: status,
        thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
        initialized: true,
      };
    });
  }

  // --- chapters ---------------------------------------------------------------
  function chapters(manga) {
    var slug = (/\/series\/([^\/?#]+)/.exec(manga.url) || [])[1];
    if (!slug) throw new Error('cannot derive series slug from ' + manga.url);
    return getHtml(abs(manga.url)).then(function (html) {
      var byUrl = {};
      var order = [];
      var re = new RegExp(
        '<a\\s+[^>]*href="((?:https?://[^"]*)?/series/' + slug +
        '/(chapter-[^"/?#]+))"[^>]*>([\\s\\S]*?)</a>', 'g');
      var m;
      while ((m = re.exec(html)) !== null) {
        var u = abs(m[1]);
        var inner = m[3];
        // The SSR page carries the chapter list twice: a static list where
        // coin-locked (timed-paywall) rows get a dark bg-black/50 overlay, and
        // an interactive/searchable list where the same rows get a bg-yellow-600
        // coin-price badge. Their reader pages have no images, so skip a URL if
        // EITHER copy is marked locked.
        if (inner.indexOf('bg-black/50') >= 0 ||
            inner.indexOf('bg-yellow-600') >= 0) continue;
        var num = parseFloat(m[2].replace(/^chapter-/, ''));
        var name = 'Chapter ' + m[2].replace(/^chapter-/, '');
        var tM = /<div[^>]*\btitle="([^"]+)"/.exec(inner);
        if (tM) name += ': ' + stripTags(tM[1]);
        var date = 0;
        var dM = /<time[^>]*dateTime="([^"]+)"/.exec(inner);
        if (dM) { var p = Date.parse(dM[1]); if (!isNaN(p)) date = p; }
        var entry = {
          url: u,
          name: decode(name),
          date_upload: date,
          chapter_number: isNaN(num) ? -1 : num,
        };
        if (!byUrl[u]) {
          byUrl[u] = entry;
          order.push(u);
        } else if (date && !byUrl[u].date_upload) {
          // A promo/"read first" button links the chapter without the row
          // metadata — prefer the real row when both appear.
          byUrl[u] = entry;
        }
      }
      var out = [];
      for (var i = 0; i < order.length; i++) out.push(byUrl[order[i]]);
      out.sort(function (a, b) { return b.chapter_number - a.chapter_number; });
      return out;
    });
  }

  // --- pages ------------------------------------------------------------------
  function pages(chapter) {
    var slug = (/\/series\/([^\/?#]+)/.exec(chapter.url) || [])[1] || '';
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var re = /<img\b([^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        var src = attr(m[1], 'data-src') || attr(m[1], 'src');
        if (!src) continue;
        src = src.replace(/^\s+|\s+$/g, '');
        if (src.indexOf('http') !== 0) continue;
        // Page images live under …/upload/series/<slug>/…; series covers use
        // /upload/series/featured/ and chapter thumbs /upload/chapter/.
        if (src.indexOf('/upload/series/') < 0) continue;
        if (src.indexOf('/featured/') >= 0) continue;
        if (seen[src]) continue; seen[src] = true;
        out.push({ index: idx++, url: src, image_url: src, headers: { Referer: BASE + '/', 'User-Agent': UA } });
      }
      if (!out.length && /Unlock this chapter|isLockedByCoins&quot;:\[0,true\]/.test(html)) {
        throw new Error('Chapter is coin-locked on ' + NAME);
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
