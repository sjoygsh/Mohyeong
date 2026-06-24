// NatoManga (MangaNato) extension for Mohyeong's JS source runtime.
// Theme: manganato/mangakakalot clone. Cloudflare-gated — relies on the
// shared cookie jar (solve once via the source-browse "Solve Cloudflare"
// action) + the default browser User-Agent stamped by the host Dio client.
//
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals: http.get/http.post, console.
// Listing methods return { mangas: [SManga], has_next_page: bool }.
//
// Structures (captured from live device DOM dumps, 2026-06):
//   listing  /manga-list/hot-manga?page=N  -> div.list-comic-item-wrap >
//              a.list-story-item[href] (manga url) > img[data-src|src] (cover);
//              h3 > a (title). Pagination: ?page=N, a.page_last.
//   search   /search/story/{slug}?page=N   -> div.story_item > a[href] (url) +
//              img (cover); h3.story_name > a (title).
//   details  /manga/{slug}                 -> ul.manga-info-text (h1 title,
//              "Author(s) :", "Status :", li.genres a), div.manga-info-pic img
//              (cover), div#contentBox (description).
//   chapters JSON  /api/manga/{slug}/chapters?page=N ->
//              data.chapters[]{chapter_name,chapter_slug,chapter_num,updated_at}
//              data.pagination{has_more} (50/page).
//   pages    /manga/{slug}/{chapter_slug}  -> div.container-chapter-reader img
//              (page images; need Referer = site root).

(function () {
  var BASE = 'https://www.natomanga.com';
  // Mirrors the host Dio default UA. The page-image CDN (2xstorage) and many
  // hotlink-protected mirrors reject non-browser agents, and CachedNetworkImage
  // uses its own client (not the host Dio), so we stamp UA + Referer per page.
  var UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36';

  // --- tiny HTML helpers (QuickJS: no DOM, regex extraction) ---------------

  function attr(tag, name) {
    if (!tag) return null;
    // Handle both double- and single-quoted attributes (the reader's <img>
    // tags use single quotes, the listing/details pages use double).
    var m = new RegExp(name + '\\s*=\\s*"([^"]*)"').exec(tag);
    if (m) return m[1];
    m = new RegExp(name + "\\s*=\\s*'([^']*)'").exec(tag);
    return m ? m[1] : null;
  }

  var ENTITIES = {
    '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"',
    '&#039;': "'", '&#39;': "'", '&apos;': "'", '&nbsp;': ' ',
    '&rsquo;': '’', '&lsquo;': '‘', '&hellip;': '…',
    '&mdash;': '—', '&ndash;': '–',
  };
  function decode(s) {
    if (!s) return s;
    s = s.replace(/&[a-z#0-9]+;/gi, function (e) {
      if (ENTITIES[e] != null) return ENTITIES[e];
      var m = /^&#(\d+);$/.exec(e);
      if (m) return String.fromCharCode(parseInt(m[1], 10));
      return e;
    });
    return s;
  }
  function stripTags(s) {
    return s ? s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim() : s;
  }

  function getHtml(url) {
    return http.get(url, { headers: { Referer: BASE + '/' } }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) {
        var snip = (r.body || '').replace(/\s+/g, ' ').substring(0, 160);
        throw new Error('HTTP ' + r.status + ' | body: ' + snip);
      }
      return r.body || '';
    });
  }
  function getJson(url) {
    return http.get(url, {
      headers: { Accept: 'application/json', Referer: BASE + '/' },
    }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return JSON.parse(r.body || 'null');
    });
  }

  function abs(url) {
    if (!url) return url;
    if (url.indexOf('//') === 0) return 'https:' + url;
    if (url.indexOf('http') === 0) return url;
    if (url.charAt(0) === '/') return BASE + url;
    return BASE + '/' + url;
  }

  function slugOf(mangaUrl) {
    // /manga/{slug} (absolute or relative). Strip query/hash and trailing /.
    var u = mangaUrl.split('#')[0].split('?')[0].replace(/\/+$/, '');
    var m = /\/manga\/([^\/]+)$/.exec(u);
    return m ? m[1] : u.substring(u.lastIndexOf('/') + 1);
  }

  // hasNextPage: scan all ?page=N in the pager and compare to current.
  function hasNext(html, page) {
    var max = page;
    var re = /[?&]page=(\d+)/g, m;
    while ((m = re.exec(html)) !== null) {
      var n = parseInt(m[1], 10);
      if (n > max) max = n;
    }
    return max > page;
  }

  // --- listing (popular / latest) ------------------------------------------

  function parseList(html) {
    var out = [];
    var blocks = html.split('list-comic-item-wrap');
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      // manga url: the list-story-item cover anchor
      var aM = /<a\s+[^>]*class="list-story-item[^"]*"[^>]*>/.exec(b);
      var aTag = aM ? aM[0] : null;
      var url = attr(aTag, 'href');
      if (!url) continue;
      var imgM = /<img\b[^>]*>/.exec(b);
      var imgTag = imgM ? imgM[0] : null;
      var cover = attr(imgTag, 'data-src') || attr(imgTag, 'src');
      // title: prefer the cover anchor title attr, else the <h3><a> text
      var title = attr(aTag, 'title');
      if (!title) {
        var h3 = /<h3>\s*<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
        title = h3 ? stripTags(h3[1]) : '';
      }
      out.push({ url: abs(url), title: decode(title || ''), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }

  function popular(page) {
    var url = BASE + '/manga-list/hot-manga?page=' + page;
    return getHtml(url).then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }

  function latest(page) {
    var url = BASE + '/manga-list/latest-manga?page=' + page;
    return getHtml(url).then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }

  // --- search --------------------------------------------------------------

  function searchSlug(query) {
    // manganato convention: lowercase, non-alphanumerics collapsed to '_'.
    return query.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  }

  function parseSearch(html) {
    var out = [];
    var blocks = html.split('class="story_item"');
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      var aM = /<a\s+href="([^"]+)"/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      var imgM = /<img\b[^>]*>/.exec(b);
      var imgTag = imgM ? imgM[0] : null;
      var cover = attr(imgTag, 'data-src') || attr(imgTag, 'src');
      var nameM = /story_name[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/.exec(b);
      var title = nameM ? stripTags(nameM[1]) : (attr(imgTag, 'alt') || '');
      out.push({ url: abs(url), title: decode(title), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }

  function search(query, page, filters) {
    var url = BASE + '/search/story/' + searchSlug(query || '') + '?page=' + page;
    return getHtml(url).then(function (html) {
      return { mangas: parseSearch(html), has_next_page: hasNext(html, page) };
    });
  }

  // --- details -------------------------------------------------------------

  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0) return 1;
    if (s.indexOf('completed') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0) return 6;
    if (s.indexOf('cancel') >= 0) return 5;
    return 0;
  }

  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var info = /<ul class="manga-info-text">([\s\S]*?)<\/ul>/.exec(html);
      var infoBlock = info ? info[1] : html;

      var titleM = /<h1>([\s\S]*?)<\/h1>/.exec(infoBlock);
      var title = titleM ? decode(stripTags(titleM[1])) : (manga.title || '');

      var picM = /<div class="manga-info-pic">[\s\S]*?<img\b([^>]*)>/.exec(html);
      var cover = picM ? (attr(picM[1], 'data-src') || attr(picM[1], 'src')) : null;

      var authorM = /Author\(s\)\s*:\s*([^<\n]+)/.exec(infoBlock);
      var author = authorM ? decode(authorM[1].trim()) : null;

      var statusM = /Status\s*:\s*([^<\n]+)/.exec(infoBlock);
      var status = mapStatus(statusM ? statusM[1] : '');

      var genres = [];
      var genM = /<li class="genres">([\s\S]*?)<\/li>/.exec(infoBlock);
      if (genM) {
        var gre = /<a[^>]*>([\s\S]*?)<\/a>/g, gm;
        while ((gm = gre.exec(genM[1])) !== null) {
          var g = stripTags(gm[1]);
          if (g) genres.push(decode(g));
        }
      }

      var description = null;
      var descM = /<div id="contentBox"[^>]*>([\s\S]*?)<\/div>/.exec(html);
      if (descM) {
        var d = descM[1];
        // drop the "<h2>...summary:</h2>" lead-in if present
        d = d.replace(/<h2>[\s\S]*?<\/h2>/, '');
        description = decode(stripTags(d));
      }

      return {
        url: manga.url,
        title: title,
        author: author,
        artist: null,
        description: description,
        genre: genres.length ? genres.join(', ') : null,
        status: status,
        thumbnail_url: cover ? abs(cover) : manga.thumbnail_url || null,
        initialized: true,
      };
    });
  }

  // --- chapters (JSON API, full list across pages) -------------------------

  function chapters(manga) {
    var slug = slugOf(manga.url);
    var all = [];
    var seen = {}; // chapter_slug -> true, for dedupe
    // The API paginates by OFFSET, not page — `?page=N` ignores N and always
    // returns the latest 50, so `?offset=N` (incrementing by the count
    // returned) is the only way to walk the full list.
    function loop(offset) {
      var url = BASE + '/api/manga/' + slug + '/chapters?offset=' + offset;
      return getJson(url).then(function (j) {
        var data = (j && j.data) || {};
        var list = data.chapters || [];
        var added = 0;
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          if (!c.chapter_slug || seen[c.chapter_slug]) continue;
          seen[c.chapter_slug] = true;
          added++;
          var num = (typeof c.chapter_num === 'number')
            ? c.chapter_num
            : parseFloat(c.chapter_num);
          all.push({
            url: BASE + '/manga/' + slug + '/' + c.chapter_slug,
            name: c.chapter_name || c.chapter_slug,
            date_upload: c.updated_at ? Date.parse(c.updated_at) : 0,
            chapter_number: isNaN(num) ? -1 : num,
          });
        }
        var pg = data.pagination || {};
        var total = (typeof pg.total === 'number') ? pg.total : 0;
        var next = offset + (list.length > 0 ? list.length : 50);
        // Continue while this batch had content AND added something new (guards
        // against the API repeating) AND we haven't reached the reported total;
        // hard cap as a safety net.
        var more = added > 0 && list.length > 0 &&
            (total === 0 || next < total) && next < 50000;
        return more ? loop(next) : all;
      });
    }
    return loop(0);
  }

  // --- pages ---------------------------------------------------------------

  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      // Narrow to the reader container so sidebar/related thumbnails are
      // excluded, then keep only true page images. Page files are numeric
      // (".../{chapter}/0.webp"); thumbnails/ads are named or off-CDN, so the
      // numeric-filename test reliably separates them even past the mid-page
      // ad banner that splits the container's <img> run.
      var region = html;
      var start = html.indexOf('container-chapter-reader');
      if (start >= 0) region = html.substring(start);
      var out = [];
      var seen = {};
      var re = /<img\b([^>]*)>/g, m, idx = 0;
      var pageFile = /\/\d+\.(?:webp|jpe?g|png|gif)(?:\?[^"']*)?$/i;
      while ((m = re.exec(region)) !== null) {
        var tag = m[1];
        var src = attr(tag, 'src') || attr(tag, 'data-src');
        if (!src || src.indexOf('http') !== 0) continue;
        if (!pageFile.test(src)) continue; // skip thumbnails / ad images
        if (seen[src]) continue;
        seen[src] = true;
        var img = abs(src);
        out.push({
          index: idx++,
          url: img,
          image_url: img,
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
      id: 'natomanga',
      name: 'NatoManga',
      lang: 'en',
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
