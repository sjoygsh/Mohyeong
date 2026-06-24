// MangaThemesia (WPMangaStream) template extension for Mohyeong's JS runtime.
// Covers the MangaThemesia cluster (rizzfables, aryascans, thunderscans, …).
// Clone = change the CONFIG block; selectors are shared. Reference site:
// rizzfables.com. Contract: register `__extension` with manifest + popular/
// latest/search/details/chapters/pages. Host globals: http.get/post, console.

(function () {
  // ===== CONFIG (per-site) =================================================
  var BASE = 'https://rizzfables.com';
  var ID = 'rizzfables';
  var NAME = 'RizzFables';
  var LANG = 'en';
  // Manga browse sub-directory: rizzfables uses /series, most use /manga.
  var DIR = 'series';
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
    '&hellip;': '…', '&mdash;': '—', '&ndash;': '–', '&#58;': ':', '&#038;': '&',
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
  function getHtml(url) {
    return http.get(url, { headers: { Referer: BASE + '/' } }).then(function (r) {
      if (!r || r.ok === false) throw new Error('network error: ' + (r && r.error));
      if (r.status < 200 || r.status >= 300) throw new Error('HTTP ' + r.status + ' for ' + url);
      return r.body || '';
    });
  }

  // --- listing (popular / latest / search) ---------------------------------
  // MangaThemesia card: div.bsx > a[href][title] + img.ts-post-image[src|data-src].
  function parseList(html) {
    var out = [];
    var seen = {};
    var blocks = html.split(/class="bsx[^"]*"/);
    for (var i = 1; i < blocks.length; i++) {
      var b = blocks[i];
      var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
      if (!aM) continue;
      var url = aM[1];
      if (url.indexOf('/series/') < 0 && url.indexOf('/manga/') < 0 &&
          url.indexOf('/komik/') < 0 && url.indexOf('/comics/') < 0) {
        continue;
      }
      if (seen[url]) continue;
      seen[url] = true;
      var imgM = /<img\b[^>]*>/.exec(b);
      var imgTag = imgM ? imgM[0] : null;
      var cover = attr(imgTag, 'data-src') || attr(imgTag, 'data-lazy-src') || attr(imgTag, 'src');
      var title = attr(aM[0], 'title');
      if (!title && imgTag) title = attr(imgTag, 'title') || attr(imgTag, 'alt');
      out.push({ url: abs(url), title: decode(title || ''), thumbnail_url: cover ? abs(cover) : null });
    }
    return out;
  }
  function hasNext(html, page) {
    return /class="[^"]*r"[^>]*>\s*<a[^>]*href[^>]*>\s*Next|hpage|<a class="next page-numbers"|\/page\/(\d+)/i.test(html) ||
      html.indexOf('page=' + (page + 1)) !== -1;
  }
  function popular(page) {
    return getHtml(BASE + '/' + DIR + '/?page=' + page + '&order=popular').then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }
  function latest(page) {
    return getHtml(BASE + '/' + DIR + '/?page=' + page + '&order=update').then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }
  function search(query, page) {
    var url = BASE + '/page/' + page + '/?s=' + encodeURIComponent(query || '');
    return getHtml(url).then(function (html) {
      return { mangas: parseList(html), has_next_page: hasNext(html, page) };
    });
  }

  // --- details -------------------------------------------------------------
  function mapStatus(s) {
    s = (s || '').toLowerCase();
    if (s.indexOf('ongoing') >= 0 || s.indexOf('publishing') >= 0) return 1;
    if (s.indexOf('completed') >= 0 || s.indexOf('finished') >= 0) return 2;
    if (s.indexOf('hiatus') >= 0) return 6;
    if (s.indexOf('cancel') >= 0 || s.indexOf('drop') >= 0) return 5;
    return 0;
  }
  function details(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var title = '';
      var ogt = /<meta property="og:title" content="([^"]*)"/.exec(html);
      if (ogt) title = ogt[1].replace(/\s*[-|–]\s*[^-|–]+$/, '');
      if (!title) {
        var h1 = /<h1[^>]*class="entry-title"[^>]*>([\s\S]*?)<\/h1>/.exec(html);
        title = h1 ? stripTags(h1[1]) : (manga.title || '');
      }
      var picM = /class="thumb"[\s\S]*?<img\b([^>]*)>/.exec(html);
      var cover = picM ? (attr(picM[1], 'data-src') || attr(picM[1], 'src')) : null;

      var genres = [];
      var gM = /class="mgen"[^>]*>([\s\S]*?)<\/span>/.exec(html) ||
        /class="seriestugenre"[^>]*>([\s\S]*?)<\/span>/.exec(html);
      if (gM) {
        var gre = /<a[^>]*>([\s\S]*?)<\/a>/g, gm;
        while ((gm = gre.exec(gM[1])) !== null) {
          var g = stripTags(gm[1]); if (g) genres.push(decode(g));
        }
      }

      // "Status" label followed by the value in an i/a/span (covers the
      // .imptdt and .tsinfo variants across MangaThemesia sites).
      var status = 0;
      var stM = /Status[\s\S]{0,40}?<(?:i|a|span)[^>]*>([^<]+)</i.exec(html);
      if (stM) status = mapStatus(stM[1]);

      // Author: a block whose class contains "author" (its first link/value),
      // or an "Author" label followed by the value.
      var author = null;
      var auM = /class="[^"]*author[^"]*"[\s\S]{0,80}?<(?:a|i|span)[^>]*>([^<]+)<\/(?:a|i|span)>/i.exec(html) ||
        /Author[\s\S]{0,40}?<(?:i|a|span)[^>]*>([^<]+)</i.exec(html);
      if (auM) {
        var au = decode(auM[1].trim());
        if (au && au.toLowerCase() !== 'author' && au !== '-') author = au;
      }

      var description = null;
      var dM = /itemprop="description"[^>]*>([\s\S]*?)<\/div>/.exec(html) ||
        /class="entry-content[^"]*"[^>]*>([\s\S]*?)<\/div>/.exec(html);
      if (dM) description = decode(stripTags(dM[1]));

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
  // div#chapterlist li > a[href] (+ .chapternum name, .chapterdate date). Skip
  // the hidden template entry (data-num="{{number}}" / href with {{ or #).
  function chapters(manga) {
    return getHtml(abs(manga.url)).then(function (html) {
      var start = html.indexOf('id="chapterlist"');
      var region = start >= 0 ? html.substring(start) : html;
      var out = [];
      var seen = {};
      var lis = region.split('<li');
      for (var i = 1; i < lis.length; i++) {
        var b = lis[i];
        var aM = /<a\s+[^>]*href="([^"]+)"[^>]*>/.exec(b);
        if (!aM) continue;
        var url = aM[1];
        if (url.indexOf('{{') >= 0 || url.charAt(0) === '#' || !/^https?:|^\//.test(url)) continue;
        if (seen[url]) continue;
        seen[url] = true;
        var nM = /class="chapternum"[^>]*>([\s\S]*?)<\/span>/.exec(b);
        var name = nM ? stripTags(nM[1]) : '';
        var dM = /class="chapterdate"[^>]*>([\s\S]*?)<\/span>/.exec(b);
        var date = 0;
        if (dM) { var p = Date.parse(stripTags(dM[1])); if (!isNaN(p)) date = p; }
        out.push({ url: abs(url), name: decode(name) || url, date_upload: date, chapter_number: -1 });
      }
      return out;
    });
  }

  // --- pages ---------------------------------------------------------------
  // div#readerarea img[src|data-src]; fall back to the ts_reader.run({...})
  // JSON some MangaThemesia sites use instead of inline images.
  function pages(chapter) {
    return getHtml(abs(chapter.url)).then(function (html) {
      var out = [];
      var seen = {};
      var idx = 0;
      var start = html.indexOf('id="readerarea"');
      if (start >= 0) {
        var region = html.substring(start);
        var end = region.indexOf('</div>\n');
        var re = /<img\b([^>]*)>/g, m;
        while ((m = re.exec(region)) !== null) {
          if (end > 0 && m.index > end + 2000) break;
          var src = attr(m[1], 'data-src') || attr(m[1], 'src');
          if (!src) continue;
          src = src.replace(/^\s+|\s+$/g, '');
          if (src.indexOf('http') !== 0) continue;
          if (/\/themes\/|logo|loading|avatar|gravatar/i.test(src)) continue;
          if (seen[src]) continue; seen[src] = true;
          out.push({ index: idx++, url: src, image_url: src, headers: { Referer: BASE + '/', 'User-Agent': UA } });
        }
      }
      if (out.length === 0) {
        var tr = /ts_reader\.run\((\{[\s\S]*?\})\);/.exec(html);
        if (tr) {
          try {
            var data = JSON.parse(tr[1]);
            var imgs = (data.sources && data.sources[0] && data.sources[0].images) || [];
            for (var j = 0; j < imgs.length; j++) {
              out.push({ index: j, url: imgs[j], image_url: imgs[j], headers: { Referer: BASE + '/', 'User-Agent': UA } });
            }
          } catch (e) { /* ignore */ }
        }
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
