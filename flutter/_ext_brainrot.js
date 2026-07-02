// Madara (WordPress manga theme) template extension for Mohyeong's JS runtime.
// Covers the large Madara cluster (manhuaplus, harimanga, kunmanga, toongod,
// manhwaclan, allporncomic, …). To clone for another Madara site, copy this
// file and change the CONFIG block (BASE/id/name/lang) — selectors are shared.
//
// Reference site authored against: manhuaplus.com (inline chapter list, no
// AJAX). Contract: register `__extension` with manifest + popular/latest/
// search/details/chapters/pages. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG (per-site) =================================================
  var BASE = 'https://brainrotcomics.com';
  var ID = 'brainrot';
  var NAME = 'Brainrot Comics';
  var LANG = 'en';
  // Manga browse sub-path. Most Madara sites use /manga/; some override it
  // (e.g. allporncomic uses /porncomic/, others /comics/ or /series/).
  var MPATH = 'manga';
  // Some Madara sites load chapters via AJAX instead of inline in the manga
  // page. manhuaplus is inline; flip to true for sites that return an empty
  // chapter list (then chapters POST to {mangaUrl}ajax/chapters/).
  var AJAX_CHAPTERS = true;
  // =========================================================================

  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  // --- tiny HTML helpers (QuickJS: no DOM) ---------------------------------

  // Cache the compiled per-name regexes — attr() runs hundreds of times per
  // listing parse and QuickJS doesn't dedupe `new RegExp`. (No /g flag, so exec
  // is stateless and safe to reuse.)
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
    '&hellip;': '…', '&mdash;': '—', '&ndash;': '–',
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

  // Cover URL picker: Madara cards stash the real image in data-src, but some
  // sites (harimanga) put a broken RELATIVE data-src and the real absolute URL
  // in src. Prefer an absolute http(s) candidate; skip lazy placeholders.
  function pickCover(s) {
    if (!s) return null;
    var cands = [attr(s, 'data-src'), attr(s, 'data-lazy-src'),
                 attr(s, 'src'), attr(s, 'data-backup')];
    var fallback = null;
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      if (!c) continue;
      c = c.replace(/^\s+|\s+$/g, '').split(/\s+/)[0];
      if (!c || /placeholder|blank|lazy|spinner|loading|^data:image/i.test(c)) continue;
      if (fallback == null) fallback = c;
      if (/^https?:\/\//.test(c)) return c;
    }
    return fallback;
  }

  function getHtml(url, opts) {
    var o = opts || {};
    o.headers = o.headers || {};
    if (!o.headers.Referer) o.headers.Referer = BASE + '/';
    return http.get(url, o).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return r.body || '';
    });
  }
  function postHtml(url, body) {
    return http.post(url, {
      headers: {
        Referer: BASE + '/',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: body,
    }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status);
      return r.body || '';
    });
  }

  // --- listing (popular / latest / search) ---------------------------------

  // Madara listing item: div.page-item-detail > .item-thumb a[href] (url) +
  // img[data-src|src] (cover); .post-title h3/h5 a (title).
  function parseList(html) {
    var out = [];
    var blocks = html.split('page-item-detail');
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      // First series link in the block — skip the site logo/banner whose
      // anchor points home. Match any known Madara series sub-path (the browse
      // path MPATH and the per-series path can differ, e.g. manhuatop browses
      // at /manga/ but its series live at /manhua/).
      var aM = /<a\s+[^>]*href="([^"]*\/(?:manga|manhua|manhwa|comics?|series|komik|porncomic|webtoons?|toons?)\/[^"]+)"[^>]*>/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      var imgM = /<img\b[^>]*>/.exec(b);
      var imgTag = imgM ? imgM[0] : null;
      var cover = pickCover(imgTag);
      // title: the post-title anchor text, else the thumb anchor's title attr.
      var title = null;
      var tM = /post-title[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
      if (tM) title = stripTags(tM[1]);
      if (!title) title = attr(aM[0], 'title') || '';
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }

  function hasNext(html, page) {
    // Madara: a "next page" nav link or another /page/N exists.
    return /class="[^"]*nav-previous|wp-pagenavi|class="[^"]*next page-numbers|m_orderby=[^"]*&(amp;)?page=|\/page\/(\d+)/i.test(html) &&
      html.indexOf('/page/' + (page + 1)) !== -1 || /next page-numbers|nav-previous/i.test(html);
  }

  // Page 1 uses the canonical /manga/ URL; /manga/page/1/ 301-redirects on some
  // Madara sites (manhwatop) and the query can be lost across the hop.
  function listUrl(orderby, page) {
    return page <= 1
      ? BASE + '/' + MPATH + '/?m_orderby=' + orderby
      : BASE + '/' + MPATH + '/page/' + page + '/?m_orderby=' + orderby;
  }
  function popular(page) {
    return getHtml(listUrl('views', page)).then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }
  function latest(page) {
    return getHtml(listUrl('latest', page)).then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }
  function search(query, page) {
    var q = encodeURIComponent(query || '');
    var url = BASE + '/page/' + page + '/?s=' + q + '&post_type=wp-manga';
    return getHtml(url).then(function (html) {
      // Search results use .c-tabs-item rows; fall back to the listing parse.
      var mangas = parseSearch(html);
      if (mangas.length === 0) mangas = parseList(html);
      return { mangas: mangas, has_next_page: hasNext(html, page) };
    });
  }

  function parseSearch(html) {
    var out = [];
    var blocks = html.split(/class="[^"]*c-tabs-item__content/);
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
      if (!aM) continue;
      var imgM = /<img\b[^>]*>/.exec(b);
      var imgTag = imgM ? imgM[0] : null;
      var cover = pickCover(imgTag);
      var tM = /post-title[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
      var title = tM ? stripTags(tM[1]) : (attr(aM[0], 'title') || '');
      out.push({ url: abs(aM[1]), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }

  // --- details -------------------------------------------------------------

  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0 || s.indexOf('publishing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0 || s.indexOf('on hold') >= 0) return 6;
    if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
    return 0;
  }

  function linksText(block) {
    var out = [];
    if (!block) return out;
    var re = /<a[^>]*>([\s\S]*?)<\/a>/g, m;
    while ((m = re.exec(block)) !== null) {
      var t = stripTags(m[1]);
      if (t) out.push(decode(t));
    }
    return out;
  }

  function section(html, cls) {
    var m = new RegExp('class="' + cls + '"[^>]*>([\\s\\S]*?)</div>').exec(html);
    return m ? m[1] : null;
  }

  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var titleM = /<div class="post-title">[\s\S]*?<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/.exec(html);
      var title = titleM ? decode(stripTags(titleM[1])) : (manga.title || '');

      var picM = /class="summary_image"[\s\S]*?<img\b([^>]*)>/.exec(html);
      var cover = picM ? pickCover(picM[1]) : null;

      var author = linksText(section(html, 'author-content')).join(', ') || null;
      var artist = linksText(section(html, 'artist-content')).join(', ') || null;
      var genres = linksText(section(html, 'genres-content'));

      // Status: the post-content_item whose heading says "Status".
      var status = 0;
      var stM = /<div class="summary-heading">\s*<h5>\s*Status[\s\S]*?<div class="summary-content">([\s\S]*?)<\/div>/i.exec(html);
      if (stM) status = mapStatus(stripTags(stM[1]));

      var description = null;
      var dM = /class="(?:summary__content|description-summary)"[^>]*>([\s\S]*?)<\/div>/.exec(html);
      if (dM) description = decode(stripTags(dM[1].replace(/<h[0-9][\s\S]*?<\/h[0-9]>/g, '')));

      return {
        url: manga.url,
        title: title,
        author: author,
        artist: artist,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        status: status,
        thumbnail_url: cover ? abs(cover) : (manga.thumbnail_url || null),
        initialized: true,
      };
    });
  }

  // --- chapters ------------------------------------------------------------

  // li.wp-manga-chapter > a[href] (name); .chapter-release-date i/a (date).
  function parseChapters(html) {
    var out = [];
    var seen = {};
    var blocks = html.split(/<li[^>]*class="[^"]*wp-manga-chapter/);
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      if (!/^https?:|^\//.test(url) || seen[url]) continue;
      seen[url] = true;
      var name = stripTags(aM[2]);
      var dM = /chapter-release-date[\s\S]*?>([\s\S]*?)<\/(?:i|a|span)>/.exec(b);
      var date = 0;
      if (dM) {
        var t = stripTags(dM[1]);
        var parsed = Date.parse(t);
        if (!isNaN(parsed)) date = parsed;
      }
      out.push({ url: abs(url), name: decode(name) || url, date_upload: date, chapter_number: -1 });
    }
    return out;
  }

  function chapters(manga) {
    if (!AJAX_CHAPTERS) {
      return getHtml(abs(manga.url)).then(parseChapters);
    }
    // AJAX variant (manhuafast et al.): chapters load into #manga-chapters-holder
    // via the site's own admin-ajax POST, which fires automatically as the page
    // JS runs. admin-ajax/ajax-chapters GETs return empty (the action is POST +
    // nonce), and a POST can't ride the WebView proxy. But on a CF-walled site
    // the page fetch ALREADY goes through the proxy's real browser, so the JS
    // runs and the chapters render inline — we just need to wait for it. Ask the
    // proxy for a longer DOM settle, then parse the inline list. (Device-proven:
    // 335 li.wp-manga-chapter render within a few seconds.)
    // webview_force: once cf_clearance is warm, a plain Dio GET returns 200 with
    // the un-rendered shell (no JS = no chapters), so force the JS-running
    // browser path regardless of CF status.
    // brainrotcomics uses LiteSpeed lazy-load: the `?style=list` chapter list
    // is server-rendered but its JS keeps only the visible rows mounted and
    // reveals the rest as the holder scrolls. The offscreen proxy never scrolls
    // on its own, so the readiness predicate drives it: scroll to the bottom
    // each poll and only report ready once the row count STOPS growing (all
    // lazy rows revealed), capped by the settle ceiling.
    return getHtml(abs(manga.url).replace(/\/?$/, '/') + '?style=list', {
      webview_force: true,
      webview_settle_ms: 20000,                // ceiling (occluded WebView is slow)
      webview_ready_js:
        "(function(){window.scrollTo(0,document.body.scrollHeight);" +
        "var n=document.querySelectorAll('li.wp-manga-chapter').length;" +
        "var p=window.__brN||0;window.__brN=n;window.__brS=(n===p)?(window.__brS||0)+1:0;" +
        "return n>0&&window.__brS>=2;})()",
    }).then(parseChapters);
  }

  // --- pages ---------------------------------------------------------------

  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var start = html.indexOf('reading-content');
      var region = start >= 0 ? html.substring(start) : html;
      var out = [];
      var seen = {};
      var re = /<img\b([^>]*)>/g, m, idx = 0;
      while ((m = re.exec(region)) !== null) {
        var tag = m[1];
        var src = attr(tag, 'data-src') || attr(tag, 'src');
        if (!src) continue;
        src = src.replace(/^\s+|\s+$/g, '');
        if (src.indexOf('http') !== 0) continue;
        // Skip the theme logo / UI chrome; page images live on a CDN path.
        if (/\/themes\/|logo|loading|dflazy|avatar|gravatar/i.test(src)) continue;
        if (seen[src]) continue;
        seen[src] = true;
        out.push({
          index: idx++,
          url: src,
          image_url: src,
          headers: { Referer: BASE + '/', 'User-Agent': UA },
        });
      }
      return out;
    });
  }

  function chapterUrl(chapter) {
    return abs(chapter.url);
  }

  __extension = {
    manifest: {
      id: ID,
      name: NAME,
      lang: LANG,
      base_url: BASE,
      version_code: 1,
      supports_latest: true,
    },
    popular: popular,
    latest: latest,
    search: search,
    details: details,
    chapters: chapters,
    pages: pages,
    chapterUrl: chapterUrl,
  };
})();
