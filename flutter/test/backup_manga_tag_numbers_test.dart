import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mohyeong/data/backup/backup_codec.dart';
import 'package:mohyeong/data/backup/models/backup_models.dart';

/// The `.tachibk` format is shared with the Kotlin app — that is the entire
/// point of it. Mihon's `BackupManga` numbers `viewer_flags` 103, `history`
/// 104, `updateStrategy` 105, `lastModifiedAt` 106, `favoriteModifiedAt` 107,
/// `excludedScanlators` 108 and `version` 109, leaving 102 to an abandoned
/// legacy `brokenHistory`. This codec wrote all seven one tag LOW, so every
/// backup the two apps exchanged disagreed about seven fields — reading
/// history and per-entry reader settings among them — while a
/// Mohyeong-to-Mohyeong round trip looked perfect, because both ends were
/// wrong in the same direction.
///
/// These read the bytes rather than round-tripping, which is the only way to
/// catch a fault that is symmetric.

/// Minimal protobuf scan: every (field, wireType) pair at the top level.
List<(int, int)> topLevelTags(Uint8List data) {
  final out = <(int, int)>[];
  var pos = 0;
  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final b = data[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
  }

  while (pos < data.length) {
    final tag = varint();
    final field = tag >> 3;
    final wire = tag & 0x7;
    out.add((field, wire));
    switch (wire) {
      case 0:
        varint();
        break;
      case 1:
        pos += 8;
        break;
      case 2:
        // Not `pos += varint()`: Dart reads the left side first, so the
        // bytes varint() consumes for the length would be thrown away.
        final len = varint();
        pos += len;
        break;
      case 5:
        pos += 4;
        break;
      default:
        fail('unknown wire type $wire');
    }
  }
  return out;
}

/// The manga sub-message out of a full backup: root tag 1, length-delimited.
Uint8List firstMangaMessage(Uint8List backup) {
  final inflated = Uint8List.fromList(gzip.decode(backup));
  var pos = 0;
  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final b = inflated[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
    }
  }

  while (pos < inflated.length) {
    final tag = varint();
    final field = tag >> 3;
    final wire = tag & 0x7;
    if (field == 1 && wire == 2) {
      final len = varint();
      return Uint8List.sublistView(inflated, pos, pos + len);
    }
    switch (wire) {
      case 0:
        varint();
        break;
      case 1:
        pos += 8;
        break;
      case 2:
        // Not `pos += varint()`: Dart reads the left side first, so the
        // bytes varint() consumes for the length would be thrown away.
        final len = varint();
        pos += len;
        break;
      case 5:
        pos += 4;
        break;
    }
  }
  fail('no manga message in the backup');
}

/// Writes a manga message with the OLD, one-low tag numbers.
Uint8List legacyMangaMessage() {
  final out = <int>[];
  void varint(int v) {
    var value = v;
    while (value >= 0x80) {
      out.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    out.add(value);
  }

  void tag(int field, int wire) => varint((field << 3) | wire);
  void str(int field, String v) {
    tag(field, 2);
    final bytes = utf8.encode(v);
    varint(bytes.length);
    out.addAll(bytes);
  }

  void int64(int field, int v) {
    tag(field, 0);
    varint(v);
  }

  varint((1 << 3) | 0);
  varint(77); // source
  str(2, '/manga/1');
  str(3, 'Legacy Entry');
  int64(102, 5); // viewerFlags, where the fork has nothing at all
  // history at 103, where the fork has viewer_flags
  tag(103, 2);
  final history = <int>[];
  {
    final url = utf8.encode('/chapter/9');
    history
      ..add((1 << 3) | 2)
      ..add(url.length)
      ..addAll(url)
      ..add((2 << 3) | 0)
      ..addAll([0xD0, 0x0F]); // lastRead 2000
    varint(history.length);
    out.addAll(history);
  }
  int64(104, 1); // updateStrategy
  int64(105, 1234); // lastModifiedAt
  int64(106, 5678); // favoriteModifiedAt
  str(107, 'Bad Scans'); // excludedScanlators
  int64(108, 3); // version
  return Uint8List.fromList(out);
}

void main() {
  test('the wire tags are Mihon\'s, field for field', () {
    final backup = Backup(
      backupManga: [
        BackupManga(
          source: 77,
          url: '/manga/1',
          title: 'Entry',
          viewerFlags: 5,
          history: [BackupHistory(url: '/chapter/9', lastRead: 2000)],
          updateStrategy: 1,
          lastModifiedAt: 1234,
          favoriteModifiedAt: 5678,
          excludedScanlators: const ['Bad Scans'],
          version: 3,
          notes: 'a note',
          initialized: true,
        ),
      ],
    );

    final tags = topLevelTags(firstMangaMessage(encodeBackup(backup)));
    final byField = {for (final (f, w) in tags) f: w};

    // 102 is the fork's abandoned brokenHistory — we must never write it.
    expect(byField.containsKey(102), isFalse);
    expect(byField[103], 0, reason: 'viewer_flags is a varint at 103');
    expect(byField[104], 2, reason: 'history is a message at 104');
    expect(byField[105], 0, reason: 'updateStrategy at 105');
    expect(byField[106], 0, reason: 'lastModifiedAt at 106');
    expect(byField[107], 0, reason: 'favoriteModifiedAt at 107');
    expect(byField[108], 2, reason: 'excludedScanlators is a string at 108');
    expect(byField[109], 0, reason: 'version at 109');
    expect(byField[110], 2, reason: 'notes at 110');
    expect(byField[111], 0, reason: 'initialized at 111');
  });

  test('what we write now reads back unchanged', () {
    final manga = BackupManga(
      source: 77,
      url: '/manga/1',
      title: 'Entry',
      viewerFlags: 5,
      history: [BackupHistory(url: '/chapter/9', lastRead: 2000)],
      updateStrategy: 1,
      lastModifiedAt: 1234,
      favoriteModifiedAt: 5678,
      excludedScanlators: const ['Bad Scans'],
      version: 3,
    );
    final back =
        decodeBackup(encodeBackup(Backup(backupManga: [manga]))).backupManga
            .single;

    expect(back.viewerFlags, 5);
    expect(back.history.single.url, '/chapter/9');
    expect(back.updateStrategy, 1);
    expect(back.lastModifiedAt, 1234);
    expect(back.favoriteModifiedAt, 5678);
    expect(back.excludedScanlators, ['Bad Scans']);
    expect(back.version, 3);
  });

  test('a backup Mohyeong already wrote still restores correctly', () {
    // Restorability: files with the old, one-low tags are out there, and the
    // wire types are what tell the two layouts apart.
    final wrapped = <int>[(1 << 3) | 2];
    final msg = legacyMangaMessage();
    var len = msg.length;
    while (len >= 0x80) {
      wrapped.add((len & 0x7F) | 0x80);
      len >>= 7;
    }
    wrapped.add(len);
    wrapped.addAll(msg);

    final decoded =
        decodeBackup(Uint8List.fromList(gzip.encode(wrapped))).backupManga
            .single;

    expect(decoded.title, 'Legacy Entry');
    expect(decoded.viewerFlags, 5, reason: 'legacy 102 is viewer_flags');
    expect(decoded.history.single.url, '/chapter/9',
        reason: 'legacy 103 is history');
    expect(decoded.updateStrategy, 1);
    expect(decoded.lastModifiedAt, 1234);
    expect(decoded.favoriteModifiedAt, 5678);
    expect(decoded.excludedScanlators, ['Bad Scans']);
    expect(decoded.version, 3);
  });
}
