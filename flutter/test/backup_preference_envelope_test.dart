import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/backup/backup_codec.dart';
import 'package:mohyeong/data/backup/models/backup_models.dart';

/// `PreferenceValue` is a kotlinx.serialization POLYMORPHIC value, so Mihon
/// writes it as a two-field envelope — `1: "…IntPreferenceValue"`,
/// `2: {1: 100}` — not as one field whose tag picks the variant. This codec
/// assumed the union shape, which desynchronised the reader on the first
/// preference of any real Mihon backup and failed the whole restore with
/// "Unknown wire type 6". Like the tag-number fault in
/// backup_manga_tag_numbers_test.dart it was symmetric, so a
/// Mohyeong-to-Mohyeong round trip looked perfect.
///
/// These assert against BYTES, which is the only way to catch that.

const _pkg = 'eu.kanade.tachiyomi.data.backup.models.';

Uint8List _varint(int v) {
  final out = <int>[];
  var value = v;
  while ((value & ~0x7F) != 0) {
    out.add((value & 0x7F) | 0x80);
    value = value >>> 7;
  }
  return Uint8List.fromList([...out, value & 0x7F]);
}

Uint8List _lenDelim(int field, List<int> payload) => Uint8List.fromList([
      ..._varint((field << 3) | 2),
      ..._varint(payload.length),
      ...payload,
    ]);

/// One `BackupPreference` exactly as Mihon's ProtoBuf emits it.
Uint8List _mihonPref(String key, String typeName, List<int> body) => _lenDelim(
      104,
      [
        ..._lenDelim(1, utf8.encode(key)),
        ..._lenDelim(2, [
          ..._lenDelim(1, utf8.encode(typeName)),
          ..._lenDelim(2, body),
        ]),
      ],
    );

Backup _decodePrefs(List<int> raw) =>
    decodeBackup(Uint8List.fromList(gzip.encode(raw)));

String _describe(BackupPreferenceValue v) => switch (v) {
      IntPreferenceValue(:final value) => 'int:$value',
      LongPreferenceValue(:final value) => 'long:$value',
      FloatPreferenceValue(:final value) => 'float:$value',
      StringPreferenceValue(:final value) => 'str:$value',
      BooleanPreferenceValue(:final value) => 'bool:$value',
      StringSetPreferenceValue(:final value) =>
        'set:${(value.toList()..sort()).join(",")}',
    };

Backup _wrap(List<BackupPreference> prefs) => Backup(
      backupManga: const [],
      backupCategories: const [],
      backupSources: const [],
      backupPreferences: prefs,
      backupSourcePreferences: const [],
      backupExtensionRepo: const [],
      backupMangaLinks: const [],
    );

void main() {
  test('reads Mihon-shaped polymorphic preference envelopes', () {
    final raw = <int>[
      // 1:{1:100} — a varint scalar at field 1 of the body.
      ..._mihonPref('custom_brightness_value', '${_pkg}IntPreferenceValue',
          [0x08, 100]),
      ..._mihonPref('pref_filter_library_unread_v2',
          '${_pkg}StringPreferenceValue', _lenDelim(1, utf8.encode('DISABLED'))),
      ..._mihonPref(
          'crop_borders_webtoon', '${_pkg}BooleanPreferenceValue', [0x08, 0x01]),
      // Mihon writes an EMPTY body for an empty set — not a missing entry.
      ..._mihonPref(
          'library_update_restriction', '${_pkg}StringSetPreferenceValue', []),
      ..._mihonPref('mark_duplicate_read_chapter_read',
          '${_pkg}StringSetPreferenceValue', [
        ..._lenDelim(1, utf8.encode('a')),
        ..._lenDelim(1, utf8.encode('b')),
      ]),
      ..._mihonPref(
          'last_used', '${_pkg}LongPreferenceValue', [0x08, 0xE8, 0x07]),
    ];

    final prefs = _decodePrefs(raw).backupPreferences;
    expect(prefs.map((p) => p.key), [
      'custom_brightness_value',
      'pref_filter_library_unread_v2',
      'crop_borders_webtoon',
      'library_update_restriction',
      'mark_duplicate_read_chapter_read',
      'last_used',
    ]);
    expect(prefs.map((p) => _describe(p.value)), [
      'int:100',
      'str:DISABLED',
      'bool:true',
      'set:',
      'set:a,b',
      'long:1000',
    ]);
  });

  test('a body kotlinx omitted entirely decodes as the default value', () {
    // kotlinx skips a field holding its type's default, so `false` / `0` /
    // `""` can arrive as an envelope with no field 2 at all.
    final raw = _lenDelim(104, [
      ..._lenDelim(1, utf8.encode('crop_borders')),
      ..._lenDelim(2, _lenDelim(1, utf8.encode('${_pkg}BooleanPreferenceValue'))),
    ]);
    final prefs = _decodePrefs(raw).backupPreferences;
    expect(_describe(prefs.single.value), 'bool:false');
  });

  test('writes the envelope Mihon expects, byte for byte', () {
    final encoded = gzip.decode(encodeBackup(_wrap([
      BackupPreference(
        key: 'custom_brightness_value',
        value: const IntPreferenceValue(100),
      ),
    ])));
    expect(
      encoded,
      _mihonPref(
        'custom_brightness_value',
        '${_pkg}IntPreferenceValue',
        [0x08, 100],
      ),
    );
  });

  test('still reads the tag-per-variant shape older Mohyeong backups used',
      () {
    // Legacy union: tag 4 = string, tag 5 = bool, tag 1 = int.
    final raw = <int>[
      ..._lenDelim(104, [
        ..._lenDelim(1, utf8.encode('legacy_string')),
        ..._lenDelim(2, _lenDelim(4, utf8.encode('hello'))),
      ]),
      ..._lenDelim(104, [
        ..._lenDelim(1, utf8.encode('legacy_bool')),
        ..._lenDelim(2, [(5 << 3) | 0, 1]),
      ]),
      ..._lenDelim(104, [
        ..._lenDelim(1, utf8.encode('legacy_int')),
        ..._lenDelim(2, [(1 << 3) | 0, 7]),
      ]),
    ];
    final prefs = _decodePrefs(raw).backupPreferences;
    expect(prefs.map((p) => _describe(p.value)),
        ['str:hello', 'bool:true', 'int:7']);
  });

  test('per-source preferences use the same envelope', () {
    final raw = _lenDelim(105, [
      ..._lenDelim(1, utf8.encode('example.source')),
      ..._lenDelim(2, [
        ..._lenDelim(1, utf8.encode('lang')),
        ..._lenDelim(2, [
          ..._lenDelim(1, utf8.encode('${_pkg}StringPreferenceValue')),
          ..._lenDelim(2, _lenDelim(1, utf8.encode('en'))),
        ]),
      ]),
    ]);
    final sp = _decodePrefs(raw).backupSourcePreferences.single;
    expect(sp.sourceKey, 'example.source');
    expect(_describe(sp.prefs.single.value), 'str:en');
  });
}
