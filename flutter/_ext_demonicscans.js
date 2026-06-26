// MangaDemon (demonicscans.org) extension for Mohyeong's JS runtime.
// Custom PHP theme, ported 1:1 from the Keiyoushi MangaDemon Kotlin source.
// Cloudflare-walled — getHtml rides the host's WebView proxy on 403.
//   popular : /advanced.php?list=N&status=all&orderby=VIEWS%20DESC
//             items div#advanced-content > div.advanced-element
//   latest  : /lastupdates.php?list=N
//             items div#updates-container > div.updates-element (skip .toffee-badge)
//   search  : /search.php?manga=Q   items body > a[href] (div.seach-right>div title)
//   details : h1.big-fat-titles / div#manga-page img / div.genres-list li /
//             div.white-font desc / div#manga-info-stats (li label, li value)
//   chapters: div#chapters-list a.chplinks  (ownText name, span yyyy-MM-dd date)
//   pages   : img.imgholder
// Contract: register `__extension`. Host globals: http.get/http.post, console.

(function () {
  // ===== CONFIG ============================================================
  var BASE = 'https://demonicscans.org';
  var ID = 'demonicscans';
  var NAME = 'Manga Demon';
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
  // Jsoup ownText(): text directly in the element, excluding nested children
  // (the demonicscans <h1> title has a nested view-count span we must drop).
  function ownText(s) {
    if (!s) return s;
    return stripTags(s.replace(/<(\w+)\b[^>]*>[\s\S]*?<\/\1>/g, ''));
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
  function firstImg(block) {
    var m = /<img\b[^>]*>/.exec(block || '');
    if (!m) return null;
    return attr(m[0], 'data-src') || attr(m[0], 'src');
  }

  // --- listing -------------------------------------------------------------
  // advanced-element: a[href] (url) + h1 (title) + img (thumb).
  function parsePopular(html) {
    var out = [];
    var seen = {};
    var blocks = html.split('advanced-element');
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      if (seen[url]) continue; seen[url] = true;
      var hM = /<h1[^>]*>([\s\S]*?)<\/h1>/.exec(b);
      var title = hM ? ownText(hM[1]) : (attr(aM[0], 'title') || '');
      var cover = firstImg(b);
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  // updates-element: first a[href] (url + title) + div.thumb img (thumb).
  function parseLatest(html) {
    var out = [];
    var seen = {};
    var blocks = html.split('updates-element');
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      if (/toffee-badge/.test(b)) continue;
      var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      if (seen[url]) continue; seen[url] = true;
      var title = attr(aM[0], 'title') || stripTags(aM[2]) || '';
      var cover = firstImg(b);
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  // search.php: body > a[href] each wrapping img + div.seach-right > div (title).
  function parseSearch(html) {
    var out = [];
    var seen = {};
    var re = /<a\s+[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g, m;
    while ((m = re.exec(html)) !== null) {
      var url = m[1];
      var inner = m[2];
      if (inner.indexOf('<img') < 0) continue;
      if (seen[url]) continue; seen[url] = true;
      var tM = /seach-right[^>]*>\s*<div[^>]*>([\s\S]*?)<\/div>/.exec(inner) ||
        /seach-right[^>]*>([\s\S]*?)<\/div>/.exec(inner);
      var title = tM ? stripTags(tM[1]) : (attr(m[0], 'title') || '');
      var cover = firstImg(inner);
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  function popular(page) {
    return getHtml(BASE + '/advanced.php?list=' + page + '&status=all&orderby=VIEWS%20DESC').then(function (html) {
      var mangas = parsePopular(html);
      return { mangas: mangas, has_next_page: mangas.length > 0 };
    });
  }
  function latest(page) {
    return getHtml(BASE + '/lastupdates.php?list=' + page).then(function (html) {
      var mangas = parseLatest(html);
      return { mangas: mangas, has_next_page: mangas.length > 0 };
    });
  }
  function search(query, page) {
    return getHtml(BASE + '/search.php?manga=' + encodeURIComponent(query || '')).then(function (html) {
      return { mangas: page > 1 ? [] : parseSearch(html), has_next_page: false };
    });
  }

  // --- details -------------------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0) return 6;
    if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
    return 0;
  }
  function statRow(html, label) {
    var re = new RegExp('<li[^>]*>\\s*' + label + '\\s*</li>\\s*<li[^>]*>([\\s\\S]*?)</li>', 'i');
    var m = re.exec(html);
    return m ? stripTags(m[1]) : null;
  }
  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var tM = /class="big-fat-titles"[^>]*>([\s\S]*?)<\/h1>/.exec(html) ||
        /<h1[^>]*class="[^"]*big-fat-titles[^"]*"[^>]*>([\s\S]*?)<\/h1>/.exec(html);
      var title = tM ? ownText(tM[1]) : (manga.title || '');

      var cM = /id="manga-page"[\s\S]*?<img\b([^>]*)>/.exec(html);
      var cover = cM ? (attr(cM[1], 'data-src') || attr(cM[1], 'src')) : null;

      var genres = [];
      var gM = /class="genres-list"[^>]*>([\s\S]*?)<\/(?:ul|div)>/.exec(html);
      if (gM) {
        var lre = /<li[^>]*>([\s\S]*?)<\/li>/g, lm;
        while ((lm = lre.exec(gM[1])) !== null) {
          var g = stripTags(lm[1]); if (g) genres.push(decode(g));
        }
      }

      var description = null;
      var dM = /class="white-font"[^>]*>([\s\S]*?)<\/div>/.exec(html);
      if (dM) description = decode(stripTags(dM[1]));

      var author = statRow(html, 'Author');
      if (author) { author = decode(author); if (author === '-' || author.toLowerCase() === 'unknown') author = null; }
      var status = mapStatus(statRow(html, 'Status') || '');

      return {
        url: manga.url,
        title: decode(title),
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
  // div#chapters-list a.chplinks : ownText = name, child span = yyyy-MM-dd.
  function chapters(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var start = html.indexOf('id="chapters-list"');
      var region = start >= 0 ? html.substring(start) : html;
      var out = [];
      var seen = {};
      var re = /<a\s+[^>]*class="[^"]*chplinks[^"]*"[^>]*>[\s\S]*?<\/a>/g, m;
      // Re-match with href + inner captured.
      var re2 = /<a\s+([^>]*)>([\s\S]*?)<\/a>/;
      while ((m = re.exec(region)) !== null) {
        var whole = m[0];
        var parts = re2.exec(whole);
        if (!parts) continue;
        var url = attr('<a ' + parts[1] + '>', 'href');
        if (!url || seen[url]) continue; seen[url] = true;
        var inner = parts[2];
        var sM = /<span[^>]*>([\s\S]*?)<\/span>/.exec(inner);
        var date = 0;
        if (sM) { var p = Date.parse(stripTags(sM[1])); if (!isNaN(p)) date = p; }
        var name = stripTags(inner.replace(/<span[\s\S]*?<\/span>/i, ''));
        out.push({ url: abs(url), name: decode(name) || url, date_upload: date, chapter_number: -1 });
      }
      return out;
    });
  }

  // --- pages ---------------------------------------------------------------
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var re = /<img\b([^>]*)>/g, m;
      while ((m = re.exec(html)) !== null) {
        if (!/imgholder/.test(m[1])) continue;
        var src = attr(m[1], 'data-src') || attr(m[1], 'src');
        if (!src) continue;
        src = abs(src.replace(/^\s+|\s+$/g, ''));
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
