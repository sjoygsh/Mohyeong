/// Manga URLs are stored the way Mihon stores them: **relative to the source's
/// own domain**.
///
/// Mihon's HTTP extensions run every parsed series link through
/// `SManga.setUrlWithoutDomain()`, so a Mihon backup carries
/// `/manga/solo-leveling/` — never `https://site.org/manga/solo-leveling/`.
/// Our extensions parsed the same links but pushed the absolute form, and
/// `(source, url)` is the identity of a series everywhere in the app. The
/// consequence, seen on device: a restored library row and the row you reach
/// by opening the same series from Browse were two different rows, the
/// in-library dimming never lit up, and migration / global-search "already in
/// library" checks missed.
///
/// Chapter URLs are deliberately left alone — for the Madara and
/// MangaThemesia clusters Mihon stores *those* absolute, and parity means
/// matching that too.
library;

/// Strips the source's own origin off [url], mirroring Mihon's
/// `setUrlWithoutDomain` (path + query + fragment, percent-decoded).
///
/// Only strips when [url] actually lives on [baseUrl]'s host: a few sources
/// hand out links on a sibling domain (a CDN, a renamed mirror), and those
/// have to stay absolute or the extension's own `abs()` would re-attach the
/// wrong base. Relative input is returned unchanged, so this is idempotent.
String relativeMangaUrl(String url, String baseUrl) {
  if (url.isEmpty || !url.startsWith('http')) return url;
  final parsed = Uri.tryParse(url);
  final base = Uri.tryParse(baseUrl);
  if (parsed == null || base == null) return url;
  if (parsed.host.isEmpty || base.host.isEmpty) return url;
  if (parsed.host.toLowerCase() != base.host.toLowerCase()) return url;

  var out = _decode(parsed.path);
  if (parsed.hasQuery) out += '?${_decode(parsed.query)}';
  if (parsed.hasFragment) out += '#${_decode(parsed.fragment)}';
  return out.isEmpty ? url : out;
}

/// Kotlin's `URI.getPath()` hands back a decoded path, and that decoded form
/// is what sits in a Mihon backup, so a matching row has to be decoded too.
String _decode(String component) {
  try {
    return Uri.decodeComponent(component);
  } on ArgumentError {
    return component;
  }
}
