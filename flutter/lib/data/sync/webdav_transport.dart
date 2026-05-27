/// WebDAV transport — single .tachibk file at a fixed path. HTTP Basic
/// auth. The merge happens client-side via [BackupRestorer]'s per-row
/// `lastModifiedAt` logic.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'sync_transport.dart';

class WebDavTransport extends SyncTransportFileStorage {
  WebDavTransport({
    required String host,
    required this.username,
    required this.password,
    required this.dio,
  }) : host = host.trimRight().replaceAll(RegExp(r'/+$'), '');

  final String host;
  final String username;
  final String password;
  final Dio dio;

  /// Same filename Mihon uses so a Mohyeong install can drop into the
  /// same WebDAV folder as an existing Mihon install with no migration.
  static const String _fileName = 'mohyeong-sync.tachibk';

  String get _fileUrl => '$host/$_fileName';

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  @override
  Future<Uint8List?> pull() async {
    try {
      final response = await dio.get<List<int>>(
        _fileUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': _authHeader},
          // We want to inspect the status code rather than throw on 404.
          validateStatus: (s) => s != null && (s == 404 || (s >= 200 && s < 300)),
        ),
      );
      if (response.statusCode == 404) return null;
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw SyncException('WebDAV auth failed (HTTP $code)');
      }
      throw SyncException('WebDAV pull failed (HTTP ${code ?? '?'})');
    }
  }

  @override
  Future<void> push(Uint8List payload) async {
    try {
      await dio.put<void>(
        _fileUrl,
        data: Stream.value(payload),
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Content-Type': 'application/octet-stream',
            'Content-Length': payload.length,
          },
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
    } on DioException catch (e) {
      throw SyncException(
          'WebDAV push failed (HTTP ${e.response?.statusCode ?? '?'})');
    }
  }
}
