import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/sync/data/remote_data_source_retrofit.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '{"status":"ok"}',
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
}
