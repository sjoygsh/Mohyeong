/// Mirror of Mihon's `ReadingMode` enum.
///
/// Stored as the low 3 bits of `mangas.viewer` (or the user's global
/// preference when the per-manga value is 0 / DEFAULT). Flag values
/// match Mihon byte-for-byte so a backup-restored library reads correctly.
library;

enum ReadingMode {
  /// Per-manga "inherit global" sentinel. Resolves to the user's
  /// chosen default when reading.
  defaultMode(0x0, 'Default'),
  leftToRight(0x1, 'Paged (left to right)'),
  rightToLeft(0x2, 'Paged (right to left)'),
  verticalPaged(0x3, 'Paged (vertical)'),
  webtoon(0x4, 'Long strip'),
  continuousVertical(0x5, 'Long strip with gaps');

  const ReadingMode(this.flagValue, this.label);

  final int flagValue;
  final String label;

  /// Width of the bitfield within `mangas.viewer`. Other reader-related
  /// settings (rotation, scaling, ...) live in higher bits, untouched
  /// here so a future migration can layer them in.
  static const int mask = 0x7;

  static ReadingMode fromFlag(int? flag) {
    if (flag == null) return ReadingMode.defaultMode;
    final v = flag & mask;
    for (final m in ReadingMode.values) {
      if (m.flagValue == v) return m;
    }
    return ReadingMode.defaultMode;
  }

  /// True if this mode uses a single-page horizontal/vertical pager
  /// rather than a continuous scroll viewport.
  bool get isPaged =>
      this == ReadingMode.leftToRight ||
      this == ReadingMode.rightToLeft ||
      this == ReadingMode.verticalPaged;

  /// True if this mode draws pages horizontally (used to drive the page
  /// view axis and the previous-page tap zone).
  bool get isHorizontal =>
      this == ReadingMode.leftToRight || this == ReadingMode.rightToLeft;
}
