/// SyncYomi backend (server-mediated). The server merges the incoming
/// snapshot against its authoritative copy and returns the merged
/// payload for the client to apply.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'sync_transport.dart';

class SyncYomiTransport extends SyncTransportServerMediated {
  SyncYomiTransport({
    required String host,
    required this.apiKey,
    required this.dio,
  }) : host = host.trimRight().replaceAll(RegExp(r'/+$'), '');

  final String host;
  final String apiKey;
  final Dio dio;

  @override
  Future<Uint8List> exchange({
    required Uint8List local,
    required int lastSyncTimestamp,
    required String deviceId,
  }) async {
    try {
      final response = await dio.post<List<int>>(
        '$host/api/sync/content',
        data: Stream.value(local),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'X-Sync-Device-Id': deviceId,
            'X-Sync-Last-Sync': lastSyncTimestamp.toString(),
            'Content-Type': 'application/octet-stream',
            'Content-Length': local.length,
          },
          // Treat all 2xx as success; let everything else throw.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw SyncException('Sync server returned empty payload');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw SyncException(
        'SyncYomi exchange failed (HTTP ${e.response?.statusCode ?? '?'})',
      );
    }
  }
}
