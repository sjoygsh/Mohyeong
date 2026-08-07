/// Shared timestamp rendering that honours the `relativeTimestampsProvider`
/// and `dateFormatProvider` appearance preferences. When relative times are
/// on, recent timestamps render as "just now / Nm ago / Nh ago / Nd ago"
/// (matching Mihon's relative style); older ones and the relative-off path
/// fall back to an absolute date formatted with the user's `app_date_format`
/// pattern.
///
/// The absolute date pattern mirrors Mihon's `DateFormats` presets
/// ("MM/dd/yy", "dd/MM/yy", "yyyy-MM-dd", "dd MMM yyyy", "MMM dd, yyyy"); an
/// empty pattern means "device default" and falls back to a locale-aware
/// short date.
library;

import 'package:intl/intl.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// One DateFormat per pattern (the empty "device default" pattern keys the
/// locale short date). Constructing a DateFormat parses the ICU pattern —
/// noticeable when every history tile did it on each scroll-in. Bounded:
/// patterns come from the fixed `app_date_format` preset list.
final Map<String, DateFormat> _formatCache = {};

/// Formats just the date portion of [t] using [pattern]. An empty [pattern]
/// uses the locale's short date (Mihon's "Default" option).
String formatDate(DateTime t, String pattern) {
  final format = _formatCache[pattern] ??=
      pattern.isEmpty ? DateFormat.yMd() : DateFormat(pattern);
  return format.format(t);
}

/// Whole CALENDAR days from [from] to [to], each taken as its local date.
///
/// Deliberately not `to.difference(from).inDays` over two midnights: a
/// [Duration] between local times measures ABSOLUTE elapsed time, so across a
/// daylight-saving change two adjacent midnights are 23 or 25 hours apart and
/// the truncating division reports 0 days for yesterday (or 1 for today).
/// Twice a year, in every DST region, that files yesterday's reading under
/// "Today". The fork counts calendar days — `ChronoUnit.DAYS.between` over
/// `LocalDate`, which has no time-of-day at all — and re-anchoring both dates
/// in UTC, where no offset shift exists, reproduces that exactly.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

String _absoluteDateTime(DateTime t, String pattern) =>
    '${formatDate(t, pattern)} ${_two(t.hour)}:${_two(t.minute)}';

/// Renders [t] for a list-row subtitle. With [relative] on, timestamps
/// within the last week use the "Nh ago" style and older ones collapse to
/// an absolute date. With [relative] off, always shows date + time. The
/// absolute date obeys the [pattern] (`app_date_format`) preference.
String formatTimestamp(
  DateTime t, {
  required bool relative,
  String pattern = 'yyyy-MM-dd',
}) {
  if (!relative) return _absoluteDateTime(t, pattern);
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(t, pattern);
}
