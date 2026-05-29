/// How page images are scaled to fit the reader viewport. Mirror of the
/// scale-type options Mihon exposes per reading mode, mapped onto the
/// Flutter [BoxFit] that produces the equivalent layout.
library;

import 'package:flutter/widgets.dart';

enum ReaderScaleType {
  fitScreen('fit_screen', 'Fit screen', BoxFit.contain),
  stretch('stretch', 'Stretch', BoxFit.fill),
  fitWidth('fit_width', 'Fit width', BoxFit.fitWidth),
  fitHeight('fit_height', 'Fit height', BoxFit.fitHeight),
  originalSize('original', 'Original size', BoxFit.none);

  const ReaderScaleType(this.key, this.label, this.boxFit);

  /// SharedPreferences-stored identifier (mirrors Mihon naming intent).
  final String key;
  final String label;

  /// The [BoxFit] applied to each page image for this scale type.
  final BoxFit boxFit;

  static ReaderScaleType fromKey(String? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return ReaderScaleType.fitScreen;
  }
}
