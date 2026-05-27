# Mohyeong extension API

Extensions are plain JavaScript files. Mohyeong loads each one into its own
sandboxed `flutter_js` runtime. The runtime exposes a minimal host API; the
extension registers its public surface by assigning to a global called
`__extension`.

This file is the only API contract. Anything not documented here is not
guaranteed to exist.

## Globals provided by the host

### `http`

```js
http.get(url, opts?)   // -> Promise<Response>
http.post(url, opts?)  // -> Promise<Response>
```

`opts` (all optional):
- `headers`: `{ [name]: value }`
- `body`: string or JSON-serialisable value (POST only)

`Response`:
- `ok` (boolean) — true if the request itself completed (NOT a 2xx check)
- `status` (number) — HTTP status code
- `body` (string) — raw response body as text
- `headers` (object) — response header map; values are comma-joined strings
- `final_url` (string) — URL after redirects
- `error` (string) — only present when `ok === false`

### `console`

```js
console.log(...args)
console.warn(...args)
console.error(...args)
```

Forwarded to the Dart side. Useful while developing.

## Required shape of `__extension`

```js
__extension = {
  manifest: {
    id: 'unique-id',          // required, stable, used as on-disk key
    name: 'Human Readable',   // required
    lang: 'en',               // required: ISO 639-1 or 'all'
    base_url: 'https://...',  // optional but recommended
    version_code: 1,          // required, bump on breaking change
    supports_latest: true,    // optional, default false
  },

  // Returns { mangas: [SManga], has_next_page: boolean }
  async popular(page) { ... },

  // Required when manifest.supports_latest === true.
  async latest(page) { ... },

  // Returns { mangas: [SManga], has_next_page: boolean }
  async search(query, page) { ... },

  // Receives a partial SManga (at minimum {url}). Returns a full SManga
  // with author/artist/description/genre/status/thumbnail_url filled in.
  async details(manga) { ... },

  // Returns an array of SChapter.
  async chapters(manga) { ... },

  // Receives an SChapter (at minimum {url}). Returns an array of SPage.
  async pages(chapter) { ... },
};
```

## Data shapes

### `SManga`

```js
{
  url: 'source-internal/path',  // required, stable key
  title: 'Title',               // required
  author: 'A',                  // optional
  artist: 'A',                  // optional
  description: 'desc',          // optional
  genre: 'tag1, tag2',          // optional (comma-separated string)
  status: 1,                    // optional, 0=Unknown 1=Ongoing 2=Completed
                                // 3=Licensed 4=Publishing Finished
                                // 5=Cancelled 6=On Hiatus
  thumbnail_url: 'https://...', // optional
}
```

### `SChapter`

```js
{
  url: 'source-internal/path',  // required
  name: 'Chapter 12',           // required
  date_upload: 1700000000000,   // optional, ms since epoch
  chapter_number: 12,           // optional, -1 if unknown
  volume_number: 1,             // optional
  scanlator: 'Group',           // optional
}
```

### `SPage`

```js
{
  index: 0,                     // required, zero-based
  url: 'https://...',           // required, source-internal page URL
  image_url: 'https://...',     // optional; reader treats null as "needs resolve"
  headers: { Referer: '...' },  // optional per-request headers
}
```

## Skeleton

```js
__extension = {
  manifest: {
    id: 'example',
    name: 'Example',
    lang: 'en',
    base_url: 'https://example.invalid',
    version_code: 1,
    supports_latest: false,
  },

  async popular(page) {
    const res = await http.get(`${this.manifest.base_url}/popular?page=${page}`);
    const body = JSON.parse(res.body);
    return {
      mangas: body.items.map((m) => ({
        url: `/manga/${m.id}`,
        title: m.title,
        thumbnail_url: m.cover,
      })),
      has_next_page: body.has_next,
    };
  },

  async search(query, page) {
    // ...
    return { mangas: [], has_next_page: false };
  },

  async details(manga) {
    const res = await http.get(this.manifest.base_url + manga.url);
    const body = JSON.parse(res.body);
    return {
      url: manga.url,
      title: body.title,
      author: body.author,
      description: body.synopsis,
      thumbnail_url: body.cover,
      status: body.ongoing ? 1 : 2,
    };
  },

  async chapters(manga) { return []; },
  async pages(chapter) { return []; },
};
```

## Notes

- Extensions run sandboxed: no `dart:io`, no Flutter, no platform APIs. Only
  what's documented above plus standard ES2017+ features.
- HTTP requests go through the host's HTTP client, so Cloudflare cookies the
  user has obtained via the in-app auto-solve apply automatically.
- Sources are loaded lazily — the runtime is only spun up the first time the
  source is opened. Don't put heavy work at the top level of the file.
