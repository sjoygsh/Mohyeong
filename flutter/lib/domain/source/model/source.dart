import 'pin.dart';

/// Mirror of `tachiyomi.domain.source.model.Source`.
class Source {
  const Source({
    required this.id,
    required this.lang,
    required this.name,
    required this.supportsLatest,
    required this.isStub,
    this.pin = Pins.unpinnedSet,
    this.isUsedLast = false,
  });

  final int id;
  final String lang;
  final String name;
  final bool supportsLatest;
  final bool isStub;
  final Pins pin;
  final bool isUsedLast;

  /// Mirrors Kotlin: "Name (LANG)" when lang is set, otherwise just "Name".
  String get visualName =>
      lang.isEmpty ? name : '$name (${lang.toUpperCase()})';

  /// Stable identifier for use as a list key.
  String get key => isUsedLast ? '$id-lastused' : '$id';

  Source copyWith({
    int? id,
    String? lang,
    String? name,
    bool? supportsLatest,
    bool? isStub,
    Pins? pin,
    bool? isUsedLast,
  }) {
    return Source(
      id: id ?? this.id,
      lang: lang ?? this.lang,
      name: name ?? this.name,
      supportsLatest: supportsLatest ?? this.supportsLatest,
      isStub: isStub ?? this.isStub,
      pin: pin ?? this.pin,
      isUsedLast: isUsedLast ?? this.isUsedLast,
    );
  }
}
