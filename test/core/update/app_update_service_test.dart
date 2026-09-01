import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/update/app_update_service.dart';

void main() {
  test(
    'appelle le contrat Android et expose version, build et mandatory',
    () async {
      final adapter = _JsonAdapter('''
      {
        "status": "ok",
        "data": {
          "available": true,
          "version": "1.2.7",
          "build": 115,
          "apk_url": "https://staging.radoran.net/web/image/72821",
          "sha256": "abcdef",
          "mandatory": true,
          "release_notes": "Correctifs"
        }
      }
    ''');
      final dio = Dio(BaseOptions(baseUrl: 'https://staging.radoran.net'))
        ..httpClientAdapter = adapter;
      final service = AppUpdateService(
        dio,
        platformBridge: const _FakePlatformBridge(
          InstalledAppVersion(version: '1.2.6', build: 114),
        ),
      );

      final check = await service.check();

      expect(adapter.request?.path, '/api/app/version');
      expect(adapter.request?.queryParameters, {'platform': 'android'});
      expect(check.currentVersion, '1.2.6');
      expect(check.currentBuild, 114);
      expect(check.update?.version, '1.2.7');
      expect(check.update?.build, 115);
      expect(check.update?.mandatory, isTrue);
    },
  );

  test(
    'ignore available=true si le build Android n’est pas supérieur',
    () async {
      final adapter = _JsonAdapter('''
      {
        "status": "ok",
        "data": {
          "available": true,
          "version": "1.2.7",
          "build": 114,
          "apk_url": "https://staging.radoran.net/web/image/72821",
          "sha256": "abcdef",
          "mandatory": false
        }
      }
    ''');
      final dio = Dio(BaseOptions(baseUrl: 'https://staging.radoran.net'))
        ..httpClientAdapter = adapter;
      final service = AppUpdateService(
        dio,
        platformBridge: const _FakePlatformBridge(
          InstalledAppVersion(version: '1.2.6', build: 114),
        ),
      );

      final check = await service.check();

      expect(check.update, isNull);
    },
  );
}

class _FakePlatformBridge implements AppUpdatePlatformBridge {
  final InstalledAppVersion installed;

  const _FakePlatformBridge(this.installed);

  @override
  bool get isSupported => true;

  @override
  Future<InstalledAppVersion> installedVersion() async => installed;

  @override
  Future<String> installApk(String path) async => 'installer_opened';
}

class _JsonAdapter implements HttpClientAdapter {
  final String body;
  RequestOptions? request;

  _JsonAdapter(this.body);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
