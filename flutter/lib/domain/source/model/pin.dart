/// Mirror of `tachiyomi.domain.source.model.Pin` (sealed object hierarchy)
/// and `Pins` (a tiny bitmask wrapper).
enum Pin {
  unpinned(0x00),
  pinned(0x01),
  actual(0x02);

  const Pin(this.code);
  final int code;
}

/// Wraps an int bitmask of Pin values.
class Pins {
  const Pins(this.code);

  final int code;

  bool contains(Pin pin) => (pin.code & code) == pin.code;

  Pins operator +(Pin pin) => Pins(code | pin.code);
  Pins operator -(Pin pin) => Pins(code ^ pin.code);

  static const Pins unpinnedSet = Pins(0x00);
  static const Pins pinnedSet = Pins(0x01 | 0x02);

  @override
  bool operator ==(Object other) => other is Pins && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
