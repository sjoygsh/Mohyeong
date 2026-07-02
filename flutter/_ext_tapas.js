// Tapas (tapas.io) extension for Mohyeong's JS runtime — FREE episodes only,
// like Mihon's Tapas source: paid/locked episodes (coin "charging" or
// wait-or-pay) are skipped, no account needed. Authored against the live
// site (2026-07-02):
//   browse  : the old /comics browse now 302s into a Next.js SPA shell, but
//             the SPA's own JSON API is open:
//             story-api.tapas.io/cosmos/api/v1/landing/ranking (popular) and
//             landing/new (latest), ?category_type=COMIC&page=N&size=20 →
//             {data:{items:[{seriesId,title,assetProperty.thumbnailImage,…}]}}
//   search  : /search?t=COMICS&q=<q>&pageNumber=N is still server-rendered
//             (cards: a[href="/series/<slug>"] + img; the alt text carries
//             #_h_i_g_h_L_i_g_h_t_# markers around the match — stripped).
//   details : /series/<id-or-slug>/info is still server-rendered (og: meta).
//   chapters: /series/<numericId>/episodes?page=N&sort=NEWEST JSON (XHR
//             headers) → data.body HTML rows (same markup on tapas.io and
//             m.tapas.io, where a mobile UA lands). NOTE the data-is-charging/
//             data-is-wait-or-pay attrs do NOT track anonymous readability —
//             on WUF ("wait until free") series wait-or-pay is true even on
//             the always-free early episodes and false on sign-in-gated ones.
//             What does track it is the row CLASS: gated rows carry
//             body__item--opaque and/or js-have-to-sign; readable rows carry
//             neither. Filter on that. info__label "Episode N", info__title.
//   pages   : /episode/<id> → img.content__img (real URL in data-src; same
//             class on m.tapas.io). Gated episodes render NO content__img at
//             all, so empty ⇒ locked. Don't sniff js-have-to-sign here: it
//             appears on every m.tapas.io page as a sign-up banner class.
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://tapas.io';
  var API = 'https://story-api.tapas.io/cosmos/api/v1';
  var ID = 'tapas';
  var NAME = 'Tapas';
  var LANG = 'en';
  var PAGE_SIZE = 20;
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
  function getJson(url) {
    return http.get(url, {
      headers: {
        Referer: BASE + '/',
        Accept: 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
      },
    }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return JSON.parse(r.body || '{}');
    });
  }

  // --- listing (cosmos JSON API) --------------------------------------------
  function mapItems(data) {
    var items = (data && data.data && data.data.items) || [];
    var mangas = [];
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      if (!it || !it.seriesId) continue;
      var thumb = it.assetProperty && it.assetProperty.thumbnailImage &&
        it.assetProperty.thumbnailImage.path;
      mangas.push({
        url: BASE + '/series/' + it.seriesId,
        title: it.title || String(it.seriesId),
        thumbnail_url: thumb || null,
      });
    }
    return { mangas: mangas, has_next_page: mangas.length >= PAGE_SIZE };
  }
  function popular(page) {
    return getJson(API + '/landing/ranking?category_type=COMIC&page=' + page +
      '&size=' + PAGE_SIZE).then(mapItems);
  }
  function latest(page) {
    // landing/new groups its items by day: items=[{day,isToday,items:[series]}]
    // — flatten the day buckets before mapping.
    return getJson(API + '/landing/new?category_type=COMIC&page=' + page +
      '&size=' + PAGE_SIZE).then(function (d) {
      var groups = (d && d.data && d.data.items) || [];
      var flat = [];
      for (var i = 0; i < groups.length; i++) {
        var inner = groups[i] && groups[i].items;
        if (inner) for (var j = 0; j < inner.length; j++) flat.push(inner[j]);
        else if (groups[i] && groups[i].seriesId) flat.push(groups[i]);
      }
      return mapItems({ data: { items: flat } });
    });
  }

  // --- search (server-rendered old web) --------------------------------------
  function search(query, page) {
    var url = BASE + '/search?t=COMICS&q=' + encodeURIComponent(query || '') +
      '&pageNumber=' + page;
    return getHtml(url).then(function (html) {
      var out = [];
      var seen = {};
      // The desktop page renders result cards as <a href="/series/…"><img …>,
      // the mobile page (m.tapas.io — where a mobile UA lands) as elements with
      // data-href="/series/…" and the <img> in a following thumb-wrap. Handle
      // both: match either attribute, then read the first img after the tag.
      var re = /<[a-z]+\b([^>]*data-href="(\/series\/[^"?#]+)"[^>]*)>|<a\b([^>]*href="(\/series\/[^"?#]+)"[^>]*)>/g;
      var m;
      while ((m = re.exec(html)) !== null) {
        var u = m[2] || m[4];
        if (!u || seen[u]) continue;
        var tail = html.substring(m.index, m.index + 1200);
        var imgM = /<img\b([^>]*)>/.exec(tail);
        if (!imgM) continue; // only thumb cards; skip text links
        seen[u] = true;
        // The alt text wraps the matched term in #_h_i_g_h_L_i_g_h_t_# markers.
        var title = (attr(imgM[1], 'alt') || '')
          .replace(/#\/?_h_i_g_h_L_i_g_h_t_#/g, '');
        out.push({
          url: abs(u),
          title: decode(title) || u,
          thumbnail_url: attr(imgM[1], 'src'),
        });
      }
      return { mangas: out, has_next_page: out.length > 0 };
    });
  }

  // --- details ---------------------------------------------------------------
  function meta(html, sel, prop) {
    var m = new RegExp('<meta[^>]+' + sel + '="' + prop + '"[^>]+content="([^"]*)"', 'i').exec(html);
    if (m) return m[1];
    m = new RegExp('<meta[^>]+content="([^"]*)"[^>]+' + sel + '="' + prop + '"', 'i').exec(html);
    return m ? m[1] : null;
  }
  function infoUrl(mangaUrl) {
    return abs(mangaUrl).replace(/\/(info)?\/?$/, '') + '/info';
  }
  function details(manga) {
    return getHtml(infoUrl(manga.url)).then(function (html) {
      var title = meta(html, 'property', 'og:title') || manga.title || '';
      title = decode(title)
        .replace(/^\s*Read\s+/i, '')
        .replace(/\s*\|\s*Tapas.*$/i, '')
        .trim();
      var cover = meta(html, 'property', 'og:image');
      var description = meta(html, 'name', 'description') ||
        meta(html, 'property', 'og:description');
      if (description) description = decode(description);

      var genres = [];
      var gre = /class="[^"]*genre-btn[^"]*"[^>]*>([\s\S]*?)<\/a>|href="\/genres\/[^"]*"[^>]*>([\s\S]*?)<\/a>/g;
      var gm;
      while ((gm = gre.exec(html)) !== null) {
        var g = decode(stripTags(gm[1] || gm[2] || ''));
        if (g && genres.indexOf(g) < 0) genres.push(g);
      }

      return {
        url: manga.url,
        title: title,
        author: null,
        artist: null,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        status: 0,
        thumbnail_url: cover || manga.thumbnail_url || null,
        initialized: true,
      };
    });
  }

  // --- chapters (free episodes only) ------------------------------------------
  function seriesNumericId(html, mangaUrl) {
    var m = /\/series\/(\d+)/.exec(mangaUrl);
    if (m) return m[1];
    m = /series[_-]?id["'\s:=]+(\d+)/i.exec(html) ||
      /data-tiara-event-meta-series-id="(\d+)"/.exec(html);
    return m ? m[1] : null;
  }
  function fetchEpisodePage(id, page, acc) {
    return getJson(BASE + '/series/' + id + '/episodes?page=' + page +
      '&sort=NEWEST&max_limit=' + PAGE_SIZE).then(function (d) {
      var data = (d && d.data) || {};
      var body = data.body || '';
      var re = /<li\b([^>]*data-href="\/episode\/\d+"[^>]*)>([\s\S]*?)<\/li>/g, m;
      while ((m = re.exec(body)) !== null) {
        var tag = m[1];
        // Gated rows (coin "charging", wait-or-pay window, sign-in-to-redeem
        // WUF pass) are greyed out via these classes; anonymous-readable rows
        // carry neither. The data-is-* attrs are NOT reliable for this — see
        // the header note.
        var cls = attr(tag, 'class') || '';
        if (cls.indexOf('body__item--opaque') >= 0) continue;
        if (cls.indexOf('js-have-to-sign') >= 0) continue;
        if (attr(tag, 'data-is-charging') === 'true') continue;
        var href = attr(tag, 'data-href');
        if (!href) continue;
        var inner = m[2];
        var tM = /info__title"[^>]*>([\s\S]*?)<\/a>/.exec(inner);
        var lM = /info__label"[^>]*>([\s\S]*?)<\/a>/.exec(inner);
        var name = tM ? decode(stripTags(tM[1])) : (lM ? decode(stripTags(lM[1])) : href);
        var num = -1;
        var nM = /Episode\s+(\d+(?:\.\d+)?)/i.exec(lM ? lM[1] : name);
        if (nM) num = parseFloat(nM[1]);
        acc.push({ url: abs(href), name: name, date_upload: 0, chapter_number: num });
      }
      var hasNext = data.pagination && data.pagination.has_next === true;
      if (hasNext && page < 100) return fetchEpisodePage(id, page + 1, acc);
      return acc;
    });
  }
  function chapters(manga) {
    return getHtml(infoUrl(manga.url)).then(function (html) {
      var id = seriesNumericId(html, abs(manga.url));
      if (!id) throw new Error('cannot resolve Tapas series id for ' + manga.url);
      return fetchEpisodePage(id, 1, []);
    });
  }

  // --- pages ------------------------------------------------------------------
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var re = /<img\b([^>]*class="[^"]*content__img[^"]*"[^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        var src = attr(m[1], 'data-src') || attr(m[1], 'src');
        if (!src || src.indexOf('http') !== 0) continue;
        // The tokenised CDN URL is HTML-escaped in the attribute
        // (…~hmac=…&amp;version=v4) — decode or the query breaks.
        src = decode(src);
        if (seen[src]) continue;
        seen[src] = true;
        out.push({
          index: out.length,
          url: src,
          image_url: src,
          headers: { Referer: BASE + '/', 'User-Agent': UA },
        });
      }
      // A gated episode serves the page chrome with zero content__img tags
      // (both hosts). js-have-to-sign is NOT a lock signal — m.tapas.io puts
      // that class on a banner on every page, free or not.
      if (!out.length) {
        throw new Error('Episode is locked or needs sign-in on ' + NAME);
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
