// MangaDex test extension for Mohyeong's JS source runtime.
// Local pipeline-test artifact (NOT for the committed repo).
// Contract: register `__extension` with manifest + popular/latest/search/
// details/chapters/pages. Host globals available: http.get/http.post, console.
// All listing endpoints return { mangas: [SManga], has_next_page: bool }.

(function () {
  var API = 'https://api.mangadex.org';
  var COVERS = 'https://uploads.mangadex.org/covers';
  var PAGE_SIZE = 20;
  var CONTENT_RATING = ['safe', 'suggestive', 'erotica'];
  var LANG = 'en';

  // --- helpers -------------------------------------------------------------

  function getJson(url) {
    return http.get(url, { headers: { Accept: 'application/json' } }).then(function (r) {
      if (!r || r.ok === false) {
        throw new Error('network error: ' + (r && r.error));
      }
      if (r.status < 200 || r.status >= 300) {
        throw new Error('HTTP ' + r.status + ' for ' + url);
      }
      return JSON.parse(r.body);
    });
  }

  function qs(params) {
    // params: array of [key, value]; supports repeated keys for [] arrays.
    var parts = [];
    for (var i = 0; i < params.length; i++) {
      var k = params[i][0], v = params[i][1];
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
    }
    return parts.join('&');
  }

  function ratingParams() {
    var out = [];
    for (var i = 0; i < CONTENT_RATING.length; i++) {
      out.push(['contentRating[]', CONTENT_RATING[i]]);
    }
    return out;
  }

  function pickTitle(attr) {
    var t = attr.title || {};
    if (t.en) return t.en;
    // try an english altTitle
    var alts = attr.altTitles || [];
    for (var i = 0; i < alts.length; i++) {
      if (alts[i].en) return alts[i].en;
    }
    // fall back to first available title value
    for (var k in t) { if (t.hasOwnProperty(k)) return t[k]; }
    return '(untitled)';
  }

  function mapStatus(s) {
    // SManga: 0 unknown,1 ongoing,2 completed,3 licensed,4 finished,5 cancelled,6 hiatus
    switch (s) {
      case 'ongoing': return 1;
      case 'completed': return 2;
      case 'hiatus': return 6;
      case 'cancelled': return 5;
      default: return 0;
    }
  }

  function findRel(data, type) {
    var rels = data.relationships || [];
    for (var i = 0; i < rels.length; i++) {
      if (rels[i].type === type) return rels[i];
    }
    return null;
  }

  function coverUrl(mangaId, data) {
    var cover = findRel(data, 'cover_art');
    if (cover && cover.attributes && cover.attributes.fileName) {
      // cover_quality source setting (host __sourcePrefs): '' = default 512.
      var size = (__sourcePrefs && __sourcePrefs.cover_quality) || '512';
      return COVERS + '/' + mangaId + '/' + cover.attributes.fileName + '.' + size + '.jpg';
    }
    return null;
  }

  function toSManga(data) {
    var attr = data.attributes || {};
    return {
      url: data.id,                      // we key manga by its id
      title: pickTitle(attr),
      thumbnail_url: coverUrl(data.id, data),
      status: mapStatus(attr.status),
    };
  }

  // --- listing endpoints ---------------------------------------------------

  function listManga(extraParams, page) {
    var offset = (page - 1) * PAGE_SIZE;
    var params = [
      ['limit', PAGE_SIZE],
      ['offset', offset],
      ['includes[]', 'cover_art'],
    ].concat(ratingParams()).concat(extraParams);
    var url = API + '/manga?' + qs(params);
    return getJson(url).then(function (json) {
      var data = json.data || [];
      var mangas = [];
      for (var i = 0; i < data.length; i++) mangas.push(toSManga(data[i]));
      var total = json.total || 0;
      return { mangas: mangas, has_next_page: offset + data.length < total };
    });
  }

  function popular(page) {
    return listManga([['order[followedCount]', 'desc']], page);
  }

  function latest(page) {
    return listManga([['order[latestUploadedChapter]', 'desc']], page);
  }

  function search(query, page, filters) {
    var params = [];
    if (query) params.push(['title', query]);
    var order = (filters && filters.order) || 'relevance';
    params.push(['order[' + order + ']', 'desc']);
    if (filters && filters.status) params.push(['status[]', filters.status]);
    if (filters && filters.demographic) {
      params.push(['publicationDemographic[]', filters.demographic]);
    }
    return listManga(params, page);
  }

  // Optional host contract: declares the search filters shown in the
  // browse filter sheet. Picks come back as the third `search` argument.
  function filters() {
    return [
      {
        key: 'status', title: 'Status', type: 'select', 'default': '',
        options: [
          { value: '', label: 'Any' },
          { value: 'ongoing', label: 'Ongoing' },
          { value: 'completed', label: 'Completed' },
          { value: 'hiatus', label: 'Hiatus' },
          { value: 'cancelled', label: 'Cancelled' },
        ],
      },
      {
        key: 'order', title: 'Sort by', type: 'select', 'default': 'relevance',
        options: [
          { value: 'relevance', label: 'Relevance' },
          { value: 'latestUploadedChapter', label: 'Latest upload' },
          { value: 'rating', label: 'Rating' },
          { value: 'followedCount', label: 'Most follows' },
        ],
      },
      {
        key: 'demographic', title: 'Demographic', type: 'select', 'default': '',
        options: [
          { value: '', label: 'Any' },
          { value: 'shounen', label: 'Shounen' },
          { value: 'shoujo', label: 'Shoujo' },
          { value: 'seinen', label: 'Seinen' },
          { value: 'josei', label: 'Josei' },
        ],
      },
    ];
  }

  // --- details -------------------------------------------------------------

  function details(manga) {
    var params = [
      ['includes[]', 'cover_art'],
      ['includes[]', 'author'],
      ['includes[]', 'artist'],
    ];
    var url = API + '/manga/' + manga.url + '?' + qs(params);
    return getJson(url).then(function (json) {
      var data = json.data;
      var attr = data.attributes || {};
      var author = findRel(data, 'author');
      var artist = findRel(data, 'artist');
      var tags = attr.tags || [];
      var genres = [];
      for (var i = 0; i < tags.length; i++) {
        var tn = tags[i].attributes && tags[i].attributes.name;
        if (tn && tn.en) genres.push(tn.en);
      }
      var desc = attr.description && (attr.description.en || '');
      return {
        url: data.id,
        title: pickTitle(attr),
        author: author && author.attributes ? author.attributes.name : null,
        artist: artist && artist.attributes ? artist.attributes.name : null,
        description: desc || null,
        genre: genres.length ? genres.join(', ') : null,
        status: mapStatus(attr.status),
        thumbnail_url: coverUrl(data.id, data),
        initialized: true,
      };
    });
  }

  // --- chapters ------------------------------------------------------------

  function fetchFeedPage(mangaId, offset) {
    var params = [
      ['limit', 500],
      ['offset', offset],
      ['translatedLanguage[]', LANG],
      ['includes[]', 'scanlation_group'],
      ['order[volume]', 'desc'],
      ['order[chapter]', 'desc'],
      ['includeExternalUrl', '0'],
    ].concat(ratingParams());
    return getJson(API + '/manga/' + mangaId + '/feed?' + qs(params));
  }

  function chapters(manga) {
    var all = [];
    function loop(offset) {
      return fetchFeedPage(manga.url, offset).then(function (json) {
        var data = json.data || [];
        for (var i = 0; i < data.length; i++) {
          var d = data[i];
          var attr = d.attributes || {};
          // skip externally-hosted chapters (no images on MangaDex)
          if (attr.externalUrl) continue;
          var grp = findRel(d, 'scanlation_group');
          var num = attr.chapter != null ? parseFloat(attr.chapter) : -1;
          var vol = attr.volume != null ? parseFloat(attr.volume) : null;
          var name = '';
          if (attr.volume) name += 'Vol.' + attr.volume + ' ';
          if (attr.chapter) name += 'Ch.' + attr.chapter;
          if (attr.title) name += (name ? ' - ' : '') + attr.title;
          if (!name) name = 'Oneshot';
          all.push({
            url: d.id,
            name: name,
            date_upload: attr.publishAt ? Date.parse(attr.publishAt) : 0,
            chapter_number: isNaN(num) ? -1 : num,
            volume_number: (vol != null && !isNaN(vol)) ? vol : null,
            scanlator: grp && grp.attributes ? grp.attributes.name : null,
          });
        }
        var total = json.total || 0;
        if (offset + data.length < total && offset < 5000) {
          return loop(offset + 500);
        }
        return all;
      });
    }
    return loop(0);
  }

  // --- pages ---------------------------------------------------------------

  function pages(chapter) {
    var url = API + '/at-home/server/' + chapter.url;
    return getJson(url).then(function (json) {
      var base = json.baseUrl;
      var hash = json.chapter && json.chapter.hash;
      // data_saver source setting (host __sourcePrefs): serve the
      // compressed page set when enabled.
      var saver = __sourcePrefs && __sourcePrefs.data_saver === 'true';
      var files = (json.chapter &&
          (saver ? json.chapter.dataSaver : json.chapter.data)) || [];
      var dir = saver ? '/data-saver/' : '/data/';
      var out = [];
      for (var i = 0; i < files.length; i++) {
        var img = base + dir + hash + '/' + files[i];
        out.push({ index: i, url: img, image_url: img });
      }
      return out;
    });
  }

  // --- chapter web URL -------------------------------------------------------

  // Optional contract method (Mohyeong host falls back to base_url + url when
  // absent). MangaDex chapter ids are bare UUIDs; the web page lives at
  // /chapter/<uuid>.
  function chapterUrl(chapter) {
    return 'https://mangadex.org/chapter/' + chapter.url;
  }

  // Optional host contract: per-source settings shown in the source's
  // settings screen; picks come back via the injected __sourcePrefs global.
  function preferences() {
    return [
      {
        key: 'data_saver', title: 'Data saver', type: 'checkbox', 'default': '',
      },
      {
        key: 'cover_quality', title: 'Cover quality', type: 'select',
        'default': '512',
        options: [
          { value: '512', label: 'Medium (512px)' },
          { value: '256', label: 'Low (256px)' },
        ],
      },
    ];
  }

  __extension = {
    manifest: {
      id: '2499283573021220255', // numeric (Mihon source-id Long) — details/persist path requires int.tryParse
      name: 'MangaDex (test)',
      lang: 'en',
      base_url: 'https://mangadex.org',
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
    filters: filters,
    preferences: preferences,
  };
})();
