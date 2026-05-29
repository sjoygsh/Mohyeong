/// Shared timestamp rendering that honours the `relativeTimestampsProvider`
/// appearance preference. When relative times are on, recent timestamps
/// render as "just now / Nm ago / Nh ago / Nd ago" (matching Mihon's
/// relative style); older ones and the relative-off path fall back to an
/// absolute date.
///
/// Absolute formatting is intentionally minimal — the app has no `intl`
/// dependency, so the custom `app_date_format` pattern isn't honoured yet
/// (it stays stored-only). We emit a fixed `yyyy-MM-dd` date, optionally
/// with `HH:mm`, which covers every current call site.
library;

String _two(int v) => v.toString().padLeft(2, '0');

String _absoluteDate(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)}';

String _absoluteDateTime(DateTime t) =>
    '${_absoluteDate(t)} ${_two(t.hour)}:${_two(t.minute)}';

/// Renders [t] for a list-row subtitle. With [relative] on, timestamps
/// within the last week use the "Nh ago" style and older ones collapse to
/// an absolute date. With [relative] off, always shows date + time.
String formatTimestamp(DateTime t, {required bool relative}) {
  if (!relative) return _absoluteDateTime(t);
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return _absoluteDate(t);
}
