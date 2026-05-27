/// Hand-rolled protobuf wire-format codec for the Mihon backup schema.
///
/// We intentionally don't depend on `package:protobuf` — that package is
/// optimised for generated code from `.proto` files and brings a lot of
/// runtime machinery we don't need. The backup schema is fixed and small
/// (a dozen messages, all primitive fields) so reading and writing the
/// wire format directly is straightforward and keeps the dependency
/// surface minimal.
///
/// Wire format spec used:
///   https://protobuf.dev/programming-guides/encoding/
///
/// kotlinx.serialization-protobuf quirks worth remembering:
///   * `Int` / `Long` / `Boolean` → varint (NOT zigzag unless tagged).
///   * `Float` → fixed32, `Double` → fixed64.
///   * `String` → length-delimited UTF-8.
///   * Repeated fields are emitted one tag-per-entry (NOT packed) for
///     non-numeric types and ALSO for numeric types when the property
///     isn't annotated with `@ProtoPacked`. Mihon's backup schema does
///     not use `@ProtoPacked` anywhere, so we always write one tag per
///     element.
///   * Nullable fields are simply omitted when null; on read, an absent
///     tag means "use the default".
///   * `encodeDefaults` is off by default in kotlinx-serialization, but
///     Mihon's `ProtoBuf {}` block doesn't override it. To match the
///     byte layout closely we also skip values that equal the schema
///     default. Mihon's restore tolerates extra fields either way.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models/backup_models.dart';

// ─── Wire types ────────────────────────────────────────────────────────────

const int _wireVarint = 0;
const int _wireFixed64 = 1;
const int _wireLengthDelim = 2;
const int _wireFixed32 = 5;

// ─── Writer ────────────────────────────────────────────────────────────────

class _ProtoWriter {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  Uint8List toBytes() => _buf.toBytes();
  int get length => _buf.length;

  void writeTag(int fieldNumber, int wireType) {
    _writeVarint((fieldNumber << 3) | wireType);
  }

  void _writeVarint(int v) {
    // Treat `v` as an unsigned 64-bit value. Dart ints are 64-bit signed
    // on the VM; the bit pattern is what protobuf cares about.
    var value = v;
    while ((value & ~0x7F) != 0) {
      _buf.addByte((value & 0x7F) | 0x80);
      // Logical right shift via unsigned semantics: mask to 64 bits then
      // shift. Dart's `>>>` is shift-right unsigned for ints.
      value = value >>> 7;
    }
    _buf.addByte(value & 0x7F);
  }

  void writeInt(int fieldNumber, int value) {
    writeTag(fieldNumber, _wireVarint);
    _writeVarint(value);
  }

  void writeBool(int fieldNumber, bool value) {
    writeTag(fieldNumber, _wireVarint);
    _buf.addByte(value ? 1 : 0);
  }

  void writeFloat(int fieldNumber, double value) {
    writeTag(fieldNumber, _wireFixed32);
    final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
    _buf.add(bytes.buffer.asUint8List());
  }

  void writeDouble(int fieldNumber, double value) {
    writeTag(fieldNumber, _wireFixed64);
    final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
    _buf.add(bytes.buffer.asUint8List());
  }

  void writeString(int fieldNumber, String value) {
    writeTag(fieldNumber, _wireLengthDelim);
    final encoded = utf8.encode(value);
    _writeVarint(encoded.length);
    _buf.add(encoded);
  }

  void writeBytes(int fieldNumber, List<int> value) {
    writeTag(fieldNumber, _wireLengthDelim);
    _writeVarint(value.length);
    _buf.add(value);
  }

  /// Nested message. We serialize the message into a child buffer first
  /// to learn its length, then emit `tag, length, payload` here.
  void writeMessage(int fieldNumber, void Function(_ProtoWriter) build) {
    final child = _ProtoWriter();
    build(child);
    final payload = child.toBytes();
    writeTag(fieldNumber, _wireLengthDelim);
    _writeVarint(payload.length);
    _buf.add(payload);
  }
}

// ─── Reader ────────────────────────────────────────────────────────────────

class _ProtoReader {
  _ProtoReader(this._data, [this._pos = 0, int? end])
      : _end = end ?? _data.length;

  final Uint8List _data;
  int _pos;
  final int _end;

  bool get isAtEnd => _pos >= _end;

  int _readByte() {
    if (_pos >= _end) {
      throw const FormatException('Unexpected end of protobuf stream');
    }
    return _data[_pos++];
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = _readByte();
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
      if (shift >= 64) {
        throw const FormatException('Varint too long');
      }
    }
  }

  int readTag() => readVarint();

  bool readBool() => readVarint() != 0;

  double readFloat() {
    final view = ByteData.sublistView(_data, _pos, _pos + 4);
    _pos += 4;
    return view.getFloat32(0, Endian.little);
  }

  double readDouble() {
    final view = ByteData.sublistView(_data, _pos, _pos + 8);
    _pos += 8;
    return view.getFloat64(0, Endian.little);
  }

  Uint8List readLengthDelimited() {
    final len = readVarint();
    final start = _pos;
    _pos += len;
    if (_pos > _end) {
      throw const FormatException('Length-delimited overflow');
    }
    return Uint8List.sublistView(_data, start, _pos);
  }

  String readString() => utf8.decode(readLengthDelimited());

  _ProtoReader readSubMessage() {
    final len = readVarint();
    final start = _pos;
    _pos += len;
    return _ProtoReader(_data, start, start + len);
  }

  /// Skip a field we don't recognise so unknown future tags don't break
  /// us — kotlinx-serialization writes them on newer schemas.
  void skipField(int wireType) {
    switch (wireType) {
      case _wireVarint:
        readVarint();
        break;
      case _wireFixed64:
        _pos += 8;
        break;
      case _wireLengthDelim:
        final len = readVarint();
        _pos += len;
        break;
      case _wireFixed32:
        _pos += 4;
        break;
      default:
        throw FormatException('Unknown wire type $wireType');
    }
  }
}

int _tagField(int tag) => tag >> 3;
int _tagWire(int tag) => tag & 0x7;

// ─── BackupChapter ─────────────────────────────────────────────────────────

void _writeBackupChapter(_ProtoWriter w, BackupChapter c) {
  w.writeString(1, c.url);
  if (c.name.isNotEmpty) w.writeString(2, c.name);
  if (c.scanlator != null) w.writeString(3, c.scanlator!);
  if (c.read) w.writeBool(4, c.read);
  if (c.bookmark) w.writeBool(5, c.bookmark);
  if (c.lastPageRead != 0) w.writeInt(6, c.lastPageRead);
  if (c.dateFetch != 0) w.writeInt(7, c.dateFetch);
  if (c.dateUpload != 0) w.writeInt(8, c.dateUpload);
  if (c.chapterNumber != -1.0) w.writeFloat(9, c.chapterNumber);
  if (c.sourceOrder != 0) w.writeInt(10, c.sourceOrder);
  if (c.lastModifiedAt != 0) w.writeInt(11, c.lastModifiedAt);
  if (c.version != 0) w.writeInt(12, c.version);
  if (c.bookmarkNote.isNotEmpty) w.writeString(13, c.bookmarkNote);
  if (c.volumeNumber != null) w.writeDouble(14, c.volumeNumber!);
}

BackupChapter _readBackupChapter(_ProtoReader r) {
  String url = '';
  String name = '';
  String? scanlator;
  bool read = false;
  bool bookmark = false;
  int lastPageRead = 0;
  int dateFetch = 0;
  int dateUpload = 0;
  double chapterNumber = -1.0;
  int sourceOrder = 0;
  int lastModifiedAt = 0;
  int version = 0;
  String bookmarkNote = '';
  double? volumeNumber;

  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        url = r.readString();
      case 2:
        name = r.readString();
      case 3:
        scanlator = r.readString();
      case 4:
        read = r.readBool();
      case 5:
        bookmark = r.readBool();
      case 6:
        lastPageRead = r.readVarint();
      case 7:
        dateFetch = r.readVarint();
      case 8:
        dateUpload = r.readVarint();
      case 9:
        chapterNumber = r.readFloat();
      case 10:
        sourceOrder = r.readVarint();
      case 11:
        lastModifiedAt = r.readVarint();
      case 12:
        version = r.readVarint();
      case 13:
        bookmarkNote = r.readString();
      case 14:
        volumeNumber = r.readDouble();
      default:
        r.skipField(_tagWire(tag));
    }
  }

  return BackupChapter(
    url: url,
    name: name,
    scanlator: scanlator,
    read: read,
    bookmark: bookmark,
    lastPageRead: lastPageRead,
    dateFetch: dateFetch,
    dateUpload: dateUpload,
    chapterNumber: chapterNumber,
    sourceOrder: sourceOrder,
    lastModifiedAt: lastModifiedAt,
    version: version,
    bookmarkNote: bookmarkNote,
    volumeNumber: volumeNumber,
  );
}

// ─── BackupCategory ────────────────────────────────────────────────────────

void _writeBackupCategory(_ProtoWriter w, BackupCategory c) {
  w.writeString(1, c.name);
  if (c.order != 0) w.writeInt(2, c.order);
  if (c.id != 0) w.writeInt(3, c.id);
  if (c.flags != 0) w.writeInt(100, c.flags);
  if (c.parentId != null) w.writeInt(101, c.parentId!);
}

BackupCategory _readBackupCategory(_ProtoReader r) {
  String name = '';
  int order = 0;
  int id = 0;
  int flags = 0;
  int? parentId;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        name = r.readString();
      case 2:
        order = r.readVarint();
      case 3:
        id = r.readVarint();
      case 100:
        flags = r.readVarint();
      case 101:
        parentId = r.readVarint();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupCategory(
    name: name,
    order: order,
    id: id,
    flags: flags,
    parentId: parentId,
  );
}

// ─── BackupHistory ─────────────────────────────────────────────────────────

void _writeBackupHistory(_ProtoWriter w, BackupHistory h) {
  w.writeString(1, h.url);
  w.writeInt(2, h.lastRead);
  if (h.readDuration != 0) w.writeInt(3, h.readDuration);
}

BackupHistory _readBackupHistory(_ProtoReader r) {
  String url = '';
  int lastRead = 0;
  int readDuration = 0;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        url = r.readString();
      case 2:
        lastRead = r.readVarint();
      case 3:
        readDuration = r.readVarint();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupHistory(url: url, lastRead: lastRead, readDuration: readDuration);
}

// ─── BackupTracking ────────────────────────────────────────────────────────

void _writeBackupTracking(_ProtoWriter w, BackupTracking t) {
  w.writeInt(1, t.syncId);
  if (t.libraryId != null) w.writeInt(2, t.libraryId!);
  // Deprecated field; we still emit it as 0 to match Mihon's behavior.
  // ignore: deprecated_member_use_from_same_package
  if (t.mediaIdInt != 0) w.writeInt(3, t.mediaIdInt);
  if (t.trackingUrl.isNotEmpty) w.writeString(4, t.trackingUrl);
  if (t.title.isNotEmpty) w.writeString(5, t.title);
  if (t.lastChapterRead != 0.0) w.writeFloat(6, t.lastChapterRead);
  if (t.totalChapters != 0) w.writeInt(7, t.totalChapters);
  if (t.score != 0.0) w.writeFloat(8, t.score);
  if (t.status != 0) w.writeInt(9, t.status);
  if (t.startedReadingDate != 0) w.writeInt(10, t.startedReadingDate);
  if (t.finishedReadingDate != 0) w.writeInt(11, t.finishedReadingDate);
  if (t.private) w.writeBool(12, t.private);
  if (t.mediaId != 0) w.writeInt(100, t.mediaId);
}

BackupTracking _readBackupTracking(_ProtoReader r) {
  int syncId = 0;
  int? libraryId;
  int mediaIdInt = 0;
  String trackingUrl = '';
  String title = '';
  double lastChapterRead = 0.0;
  int totalChapters = 0;
  double score = 0.0;
  int status = 0;
  int startedReadingDate = 0;
  int finishedReadingDate = 0;
  bool private = false;
  int mediaId = 0;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        syncId = r.readVarint();
      case 2:
        libraryId = r.readVarint();
      case 3:
        mediaIdInt = r.readVarint();
      case 4:
        trackingUrl = r.readString();
      case 5:
        title = r.readString();
      case 6:
        lastChapterRead = r.readFloat();
      case 7:
        totalChapters = r.readVarint();
      case 8:
        score = r.readFloat();
      case 9:
        status = r.readVarint();
      case 10:
        startedReadingDate = r.readVarint();
      case 11:
        finishedReadingDate = r.readVarint();
      case 12:
        private = r.readBool();
      case 100:
        mediaId = r.readVarint();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupTracking(
    syncId: syncId,
    libraryId: libraryId,
    mediaIdInt: mediaIdInt,
    trackingUrl: trackingUrl,
    title: title,
    lastChapterRead: lastChapterRead,
    totalChapters: totalChapters,
    score: score,
    status: status,
    startedReadingDate: startedReadingDate,
    finishedReadingDate: finishedReadingDate,
    private: private,
    mediaId: mediaId,
  );
}

// ─── BackupSource ──────────────────────────────────────────────────────────

void _writeBackupSource(_ProtoWriter w, BackupSource s) {
  w.writeString(1, s.name);
  w.writeInt(2, s.sourceId);
}

BackupSource _readBackupSource(_ProtoReader r) {
  String name = '';
  int sourceId = 0;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        name = r.readString();
      case 2:
        sourceId = r.readVarint();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupSource(name: name, sourceId: sourceId);
}

// ─── BackupPreference & value union ────────────────────────────────────────
//
// Mihon stores the discriminator as a sealed-class subtype name in its
// custom serializer. The wire encoding is: a single length-delimited
// field whose tag identifies the variant:
//   tag 1 → IntPreferenceValue (varint int32)
//   tag 2 → LongPreferenceValue (varint int64)
//   tag 3 → FloatPreferenceValue (fixed32)
//   tag 4 → StringPreferenceValue (length-delim string)
//   tag 5 → BooleanPreferenceValue (varint 0/1)
//   tag 6 → StringSetPreferenceValue (length-delim message containing
//           repeated string at tag 1)
//
// These tag numbers match `PreferenceValueSerializer` in Mihon.

void _writePreferenceValue(_ProtoWriter w, BackupPreferenceValue v) {
  switch (v) {
    case IntPreferenceValue(:final value):
      w.writeInt(1, value);
    case LongPreferenceValue(:final value):
      w.writeInt(2, value);
    case FloatPreferenceValue(:final value):
      w.writeFloat(3, value);
    case StringPreferenceValue(:final value):
      w.writeString(4, value);
    case BooleanPreferenceValue(:final value):
      w.writeBool(5, value);
    case StringSetPreferenceValue(:final value):
      w.writeMessage(6, (mw) {
        for (final s in value) {
          mw.writeString(1, s);
        }
      });
  }
}

BackupPreferenceValue _readPreferenceValue(_ProtoReader r) {
  // Exactly one variant is present; read the first tag, decode, then
  // tolerate any trailing fields by skipping them.
  BackupPreferenceValue? out;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        out = IntPreferenceValue(r.readVarint());
      case 2:
        out = LongPreferenceValue(r.readVarint());
      case 3:
        out = FloatPreferenceValue(r.readFloat());
      case 4:
        out = StringPreferenceValue(r.readString());
      case 5:
        out = BooleanPreferenceValue(r.readBool());
      case 6:
        final sub = r.readSubMessage();
        final set = <String>{};
        while (!sub.isAtEnd) {
          final stag = sub.readTag();
          if (_tagField(stag) == 1) {
            set.add(sub.readString());
          } else {
            sub.skipField(_tagWire(stag));
          }
        }
        out = StringSetPreferenceValue(set);
      default:
        r.skipField(_tagWire(tag));
    }
  }
  if (out == null) {
    throw const FormatException('Empty BackupPreferenceValue');
  }
  return out;
}

void _writeBackupPreference(_ProtoWriter w, BackupPreference p) {
  w.writeString(1, p.key);
  w.writeMessage(2, (mw) => _writePreferenceValue(mw, p.value));
}

BackupPreference _readBackupPreference(_ProtoReader r) {
  String key = '';
  BackupPreferenceValue? value;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        key = r.readString();
      case 2:
        value = _readPreferenceValue(r.readSubMessage());
      default:
        r.skipField(_tagWire(tag));
    }
  }
  if (value == null) {
    throw const FormatException('BackupPreference missing value');
  }
  return BackupPreference(key: key, value: value);
}

void _writeBackupSourcePreferences(_ProtoWriter w, BackupSourcePreferences sp) {
  w.writeString(1, sp.sourceKey);
  for (final p in sp.prefs) {
    w.writeMessage(2, (mw) => _writeBackupPreferenceFields(mw, p));
  }
}

void _writeBackupPreferenceFields(_ProtoWriter w, BackupPreference p) {
  w.writeString(1, p.key);
  w.writeMessage(2, (mw) => _writePreferenceValue(mw, p.value));
}

BackupSourcePreferences _readBackupSourcePreferences(_ProtoReader r) {
  String sourceKey = '';
  final prefs = <BackupPreference>[];
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        sourceKey = r.readString();
      case 2:
        prefs.add(_readBackupPreference(r.readSubMessage()));
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupSourcePreferences(sourceKey: sourceKey, prefs: prefs);
}

// ─── BackupMangaLink ───────────────────────────────────────────────────────

void _writeBackupMangaLink(_ProtoWriter w, BackupMangaLink l) {
  w.writeInt(1, l.primarySource);
  w.writeString(2, l.primaryUrl);
  w.writeInt(3, l.linkedSource);
  w.writeString(4, l.linkedUrl);
  if (l.priority != 0) w.writeInt(5, l.priority);
}

BackupMangaLink _readBackupMangaLink(_ProtoReader r) {
  int primarySource = 0;
  String primaryUrl = '';
  int linkedSource = 0;
  String linkedUrl = '';
  int priority = 0;
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        primarySource = r.readVarint();
      case 2:
        primaryUrl = r.readString();
      case 3:
        linkedSource = r.readVarint();
      case 4:
        linkedUrl = r.readString();
      case 5:
        priority = r.readVarint();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupMangaLink(
    primarySource: primarySource,
    primaryUrl: primaryUrl,
    linkedSource: linkedSource,
    linkedUrl: linkedUrl,
    priority: priority,
  );
}

// ─── BackupExtensionRepos ──────────────────────────────────────────────────

void _writeBackupExtensionRepos(_ProtoWriter w, BackupExtensionRepos r) {
  w.writeString(1, r.baseUrl);
  w.writeString(2, r.name);
  w.writeString(3, r.shortName);
  w.writeString(4, r.website);
  w.writeString(5, r.signingKeyFingerprint);
}

BackupExtensionRepos _readBackupExtensionRepos(_ProtoReader r) {
  String baseUrl = '';
  String name = '';
  String shortName = '';
  String website = '';
  String signingKeyFingerprint = '';
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        baseUrl = r.readString();
      case 2:
        name = r.readString();
      case 3:
        shortName = r.readString();
      case 4:
        website = r.readString();
      case 5:
        signingKeyFingerprint = r.readString();
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return BackupExtensionRepos(
    baseUrl: baseUrl,
    name: name,
    shortName: shortName,
    website: website,
    signingKeyFingerprint: signingKeyFingerprint,
  );
}

// ─── BackupManga ───────────────────────────────────────────────────────────

void _writeBackupManga(_ProtoWriter w, BackupManga m) {
  w.writeInt(1, m.source);
  w.writeString(2, m.url);
  if (m.title.isNotEmpty) w.writeString(3, m.title);
  if (m.artist != null) w.writeString(4, m.artist!);
  if (m.author != null) w.writeString(5, m.author!);
  if (m.description != null) w.writeString(6, m.description!);
  for (final g in m.genre) {
    w.writeString(7, g);
  }
  if (m.status != 0) w.writeInt(8, m.status);
  if (m.thumbnailUrl != null) w.writeString(9, m.thumbnailUrl!);
  if (m.dateAdded != 0) w.writeInt(13, m.dateAdded);
  if (m.viewer != 0) w.writeInt(14, m.viewer);
  for (final c in m.chapters) {
    w.writeMessage(16, (mw) => _writeBackupChapter(mw, c));
  }
  for (final c in m.categories) {
    w.writeInt(17, c);
  }
  for (final t in m.tracking) {
    w.writeMessage(18, (mw) => _writeBackupTracking(mw, t));
  }
  if (!m.favorite) w.writeBool(100, m.favorite);
  if (m.chapterFlags != 0) w.writeInt(101, m.chapterFlags);
  if (m.viewerFlags != null) w.writeInt(102, m.viewerFlags!);
  for (final h in m.history) {
    w.writeMessage(103, (mw) => _writeBackupHistory(mw, h));
  }
  if (m.updateStrategy != 0) w.writeInt(104, m.updateStrategy);
  if (m.lastModifiedAt != 0) w.writeInt(105, m.lastModifiedAt);
  if (m.favoriteModifiedAt != null) w.writeInt(106, m.favoriteModifiedAt!);
  for (final s in m.excludedScanlators) {
    w.writeString(107, s);
  }
  if (m.version != 0) w.writeInt(108, m.version);
  if (m.notes.isNotEmpty) w.writeString(110, m.notes);
  if (m.initialized) w.writeBool(111, m.initialized);
}

BackupManga _readBackupManga(_ProtoReader r) {
  int source = 0;
  String url = '';
  String title = '';
  String? artist;
  String? author;
  String? description;
  final genre = <String>[];
  int status = 0;
  String? thumbnailUrl;
  int dateAdded = 0;
  int viewer = 0;
  final chapters = <BackupChapter>[];
  final categories = <int>[];
  final tracking = <BackupTracking>[];
  bool favorite = true;
  int chapterFlags = 0;
  int? viewerFlags;
  final history = <BackupHistory>[];
  int updateStrategy = 0;
  int lastModifiedAt = 0;
  int? favoriteModifiedAt;
  final excludedScanlators = <String>[];
  int version = 0;
  String notes = '';
  bool initialized = false;

  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        source = r.readVarint();
      case 2:
        url = r.readString();
      case 3:
        title = r.readString();
      case 4:
        artist = r.readString();
      case 5:
        author = r.readString();
      case 6:
        description = r.readString();
      case 7:
        genre.add(r.readString());
      case 8:
        status = r.readVarint();
      case 9:
        thumbnailUrl = r.readString();
      case 13:
        dateAdded = r.readVarint();
      case 14:
        viewer = r.readVarint();
      case 16:
        chapters.add(_readBackupChapter(r.readSubMessage()));
      case 17:
        categories.add(r.readVarint());
      case 18:
        tracking.add(_readBackupTracking(r.readSubMessage()));
      case 100:
        favorite = r.readBool();
      case 101:
        chapterFlags = r.readVarint();
      case 102:
        viewerFlags = r.readVarint();
      case 103:
        history.add(_readBackupHistory(r.readSubMessage()));
      case 104:
        updateStrategy = r.readVarint();
      case 105:
        lastModifiedAt = r.readVarint();
      case 106:
        favoriteModifiedAt = r.readVarint();
      case 107:
        excludedScanlators.add(r.readString());
      case 108:
        version = r.readVarint();
      case 110:
        notes = r.readString();
      case 111:
        initialized = r.readBool();
      default:
        r.skipField(_tagWire(tag));
    }
  }

  return BackupManga(
    source: source,
    url: url,
    title: title,
    artist: artist,
    author: author,
    description: description,
    genre: genre,
    status: status,
    thumbnailUrl: thumbnailUrl,
    dateAdded: dateAdded,
    viewer: viewer,
    chapters: chapters,
    categories: categories,
    tracking: tracking,
    favorite: favorite,
    chapterFlags: chapterFlags,
    viewerFlags: viewerFlags,
    history: history,
    updateStrategy: updateStrategy,
    lastModifiedAt: lastModifiedAt,
    favoriteModifiedAt: favoriteModifiedAt,
    excludedScanlators: excludedScanlators,
    version: version,
    notes: notes,
    initialized: initialized,
  );
}

// ─── Backup (top-level) ────────────────────────────────────────────────────

Uint8List _encodeBackup(Backup b) {
  final w = _ProtoWriter();
  for (final m in b.backupManga) {
    w.writeMessage(1, (mw) => _writeBackupManga(mw, m));
  }
  for (final c in b.backupCategories) {
    w.writeMessage(2, (mw) => _writeBackupCategory(mw, c));
  }
  for (final s in b.backupSources) {
    w.writeMessage(101, (mw) => _writeBackupSource(mw, s));
  }
  for (final p in b.backupPreferences) {
    w.writeMessage(104, (mw) => _writeBackupPreference(mw, p));
  }
  for (final sp in b.backupSourcePreferences) {
    w.writeMessage(105, (mw) => _writeBackupSourcePreferences(mw, sp));
  }
  for (final er in b.backupExtensionRepo) {
    w.writeMessage(106, (mw) => _writeBackupExtensionRepos(mw, er));
  }
  for (final l in b.backupMangaLinks) {
    w.writeMessage(107, (mw) => _writeBackupMangaLink(mw, l));
  }
  return w.toBytes();
}

Backup _decodeBackup(Uint8List bytes) {
  final r = _ProtoReader(bytes);
  final manga = <BackupManga>[];
  final categories = <BackupCategory>[];
  final sources = <BackupSource>[];
  final preferences = <BackupPreference>[];
  final sourcePreferences = <BackupSourcePreferences>[];
  final extensionRepos = <BackupExtensionRepos>[];
  final mangaLinks = <BackupMangaLink>[];
  while (!r.isAtEnd) {
    final tag = r.readTag();
    switch (_tagField(tag)) {
      case 1:
        manga.add(_readBackupManga(r.readSubMessage()));
      case 2:
        categories.add(_readBackupCategory(r.readSubMessage()));
      case 101:
        sources.add(_readBackupSource(r.readSubMessage()));
      case 104:
        preferences.add(_readBackupPreference(r.readSubMessage()));
      case 105:
        sourcePreferences.add(_readBackupSourcePreferences(r.readSubMessage()));
      case 106:
        extensionRepos.add(_readBackupExtensionRepos(r.readSubMessage()));
      case 107:
        mangaLinks.add(_readBackupMangaLink(r.readSubMessage()));
      default:
        r.skipField(_tagWire(tag));
    }
  }
  return Backup(
    backupManga: manga,
    backupCategories: categories,
    backupSources: sources,
    backupPreferences: preferences,
    backupSourcePreferences: sourcePreferences,
    backupExtensionRepo: extensionRepos,
    backupMangaLinks: mangaLinks,
  );
}

// ─── Public API ────────────────────────────────────────────────────────────

/// Encode + gzip a [Backup] into a `.tachibk` payload that Mihon can read.
/// Mihon's backup file is always gzip-wrapped.
Uint8List encodeBackup(Backup backup) {
  final raw = _encodeBackup(backup);
  return Uint8List.fromList(gzip.encode(raw));
}

/// Decode a gzip-wrapped `.tachibk` payload into [Backup]. Tolerates
/// already-decompressed input (older debug exports sometimes wrote raw
/// protobuf) by detecting the gzip magic header.
Backup decodeBackup(Uint8List bytes) {
  final inflated = _looksLikeGzip(bytes)
      ? Uint8List.fromList(gzip.decode(bytes))
      : bytes;
  return _decodeBackup(inflated);
}

bool _looksLikeGzip(Uint8List bytes) {
  return bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;
}
