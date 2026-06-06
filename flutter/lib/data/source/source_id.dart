import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Resolves an extension's string id (its on-disk directory name / manifest
/// `id`) to the 64-bit integer source id that `mangas.source` stores.
///
/// This mirrors Mihon's `HttpSource.generateId`:
///
/// ```kotlin
/// val key = "${name.lowercase()}/$lang/$versionId"
/// val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
/// (0..7).map { bytes[it].toLong() and 0xff shl 8 * (7 - it) }
///   .reduce(Long::or) and Long.MAX_VALUE
/// ```
///
/// In Mohyeong the manifest already ships the precomputed id as its `id`
/// string for HTTP sources, so for those the slug *is* the decimal form of
/// that Long and [int.tryParse] resolves it directly — that path is kept
/// first so existing installed sources (and library rows that stored a
/// numeric-string source id) keep resolving to the exact same int.
///
/// Non-numeric slugs (a custom/local-style id, or a future extension that
/// ships a human-readable id) fall back to the MD5 derivation so they map
/// to a stable, collision-resistant 64-bit non-negative int the same way
/// Kotlin would.
int sourceNumericId(String key) {
  final parsed = int.tryParse(key);
  if (parsed != null) return parsed;

  final bytes = md5.convert(utf8.encode(key)).bytes;
  var id = 0;
  for (var i = 0; i < 8; i++) {
    id = (id << 8) | (bytes[i] & 0xff);
  }
  // Clear the sign bit so the result is always non-negative, matching
  // Kotlin's `and Long.MAX_VALUE`.
  return id & 0x7FFFFFFFFFFFFFFF;
}
