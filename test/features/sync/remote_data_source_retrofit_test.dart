import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/sync/data/remote_data_source_retrofit.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? request;
  final String responseBody;

  _CaptureAdapter([this.responseBody = '{"status":"ok"}']);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('uploadPhoto envoie un multipart plat pour une seule photo', () async {
    final tmp = File('${Directory.systemTemp.path}/mica_retrofit_photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    final remote = RetrofitRemoteDataSource(OdooApi(dio), dio);

    await remote.uploadPhoto(
      'device-uuid',
      '11111111-1111-4111-8111-111111111111',
      PhotoPart('mine', tmp.path, 'photo-hash'),
    );

    final request = adapter.request!;
    expect(request.path, '/api/attachments');
    final form = request.data as FormData;
    expect(Map.fromEntries(form.fields), {
      'device_uuid': 'device-uuid',
      'payload_id': '11111111-1111-4111-8111-111111111111',
      'key': 'mine',
      'hash': 'photo-hash',
    });
    expect(form.files.single.key, 'file');
  });

  test('uploadMinePhoto ajoute entity_type mine', () async {
    final tmp = File('${Directory.systemTemp.path}/mica_mine_position.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    final remote = RetrofitRemoteDataSource(OdooApi(dio), dio);

    await remote.uploadMinePhoto(
      'device-uuid',
      'payload-uuid',
      PhotoPart('position_1', tmp.path, 'photo-hash'),
    );

    final request = adapter.request!;
    expect(request.path, '/api/attachments');
    expect(Map.fromEntries((request.data as FormData).fields), {
      'entity_type': 'mine',
      'device_uuid': 'device-uuid',
      'payload_id': 'payload-uuid',
      'key': 'position_1',
      'hash': 'photo-hash',
    });
  });

  test('une opération mine utilise POST /api/mine', () async {
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    final remote = RetrofitRemoteDataSource(OdooApi(dio), dio);

    await remote.pushOperation(
      SyncOperation(
        opId: 'device-uuid',
        entityType: 'mine_submission',
        entityId: 'payload-uuid',
        opType: SyncOpType.create,
        payload: const {
          'id': 'payload-uuid',
          'name': 'Mine test',
          'commune_id': 24091,
        },
        createdAt: DateTime.utc(2026, 7, 30),
        agentLogin: 'eddy',
      ),
    );

    expect(adapter.request!.path, '/api/mine');
    final body = adapter.request!.data as Map<String, dynamic>;
    expect(body['device_uuid'], 'device-uuid');
    expect(body['payload'], {
      'id': 'payload-uuid',
      'name': 'Mine test',
      'commune_id': 24091,
    });
    expect(body.containsKey('collect_type'), isFalse);
  });

  test('lit le statut approved et la mine canonique', () async {
    final adapter = _CaptureAdapter('''
      {
        "status": "ok",
        "data": {
          "payload_id": "payload-uuid",
          "state": "approved",
          "rejection_reason": null,
          "mine": {
            "id": 42,
            "name": "Mine validée",
            "lat": -18.91,
            "lon": 47.52,
            "radius_m": 20,
            "active": true
          }
        }
      }
    ''');
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    final remote = RetrofitRemoteDataSource(OdooApi(dio), dio);

    final status = await remote.fetchMineSubmissionStatus('payload-uuid');

    expect(adapter.request!.path, '/api/mine/submissions/payload-uuid');
    expect(status.state, 'approved');
    expect(status.mine?.id, '42');
    expect(status.mine?.nom, 'Mine validée');
  });
}
