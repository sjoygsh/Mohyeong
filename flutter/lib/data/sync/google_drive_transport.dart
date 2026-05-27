/// Google Drive transport. Stores a single .tachibk file in the user's
/// Drive root. Auth uses a bearer access token minted by the user (e.g.
/// via the OAuth Playground with scope
/// `https://www.googleapis.com/auth/drive.file`). Token refresh is the
/// user's problem for v1.0 — same as Mihon.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'sync_transport.dart';

class GoogleDriveTransport extends SyncTransportFileStorage {
  GoogleDriveTransport({required this.accessToken, required this.dio});

  final String accessToken;
  final Dio dio;

  static const String _driveApi = 'https://www.googleapis.com/drive/v3';
  static const String _uploadApi =
      'https://www.googleapis.com/upload/drive/v3';
  static const String _fileName = 'mohyeong-sync.tachibk';

  @override
  Future<Uint8List?> pull() async {
    final fileId = await _lookupFileId();
    if (fileId == null) return null;
    try {
      final response = await dio.get<List<int>>(
        '$_driveApi/files/$fileId',
        queryParameters: {'alt': 'media'},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (s) =>
              s != null && (s == 404 || (s >= 200 && s < 300)),
        ),
      );
      if (response.statusCode == 404) return null;
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw SyncException('Drive auth failed (HTTP $code)');
      }
      throw SyncException('Drive pull failed (HTTP ${code ?? '?'})');
    }
  }

  @override
  Future<void> push(Uint8List payload) async {
    final existing = await _lookupFileId();
    try {
      if (existing == null) {
        // Multipart create. Mihon streams off disk via OkHttp; we just
        // build a single bytes payload because Dart's HTTP libs handle
        // megabyte-sized buffers cheaply and library snapshots stay
        // well under that ceiling in practice.
        final boundary =
            'mohyeong_sync_${DateTime.now().microsecondsSinceEpoch}';
        final metadata = jsonEncode({'name': _fileName});
        final builder = BytesBuilder(copy: false)
          ..add(utf8.encode('--$boundary\r\n'
              'Content-Type: application/json; charset=UTF-8\r\n\r\n'
              '$metadata\r\n'
              '--$boundary\r\n'
              'Content-Type: application/octet-stream\r\n\r\n'))
          ..add(payload)
          ..add(utf8.encode('\r\n--$boundary--'));
        final body = builder.toBytes();

        await dio.post<void>(
          '$_uploadApi/files',
          queryParameters: {'uploadType': 'multipart'},
          data: Stream.value(body),
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'multipart/related; boundary=$boundary',
              'Content-Length': body.length,
            },
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
      } else {
        await dio.patch<void>(
          '$_uploadApi/files/$existing',
          queryParameters: {'uploadType': 'media'},
          data: Stream.value(payload),
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/octet-stream',
              'Content-Length': payload.length,
            },
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
      }
    } on DioException catch (e) {
      throw SyncException(
          'Drive push failed (HTTP ${e.response?.statusCode ?? '?'})');
    }
  }

  Future<String?> _lookupFileId() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_driveApi/files',
        queryParameters: {
          'q': "name='$_fileName' and trashed=false",
          'spaces': 'drive',
          'fields': 'files(id,name)',
          'pageSize': '1',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final files = response.data?['files'] as List<dynamic>?;
      if (files == null || files.isEmpty) return null;
      final id = (files.first as Map<String, dynamic>)['id'] as String?;
      return (id == null || id.isEmpty) ? null : id;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw SyncException('Drive auth failed (HTTP $code)');
      }
      throw SyncException('Drive lookup failed (HTTP ${code ?? '?'})');
    }
  }
}
