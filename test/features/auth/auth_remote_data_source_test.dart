import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/auth/data/auth_remote_data_source.dart';

class _RoutingAdapter implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final body = switch (options.path) {
      '/api/login' =>
        '{"status":"ok","data":{"token":"token","agent":{"login":"eddy","name":"Eddy"}}}',
      '/api/mine' => '{"status":"ok","data":[]}',
      '/api/storage' => '{"status":"ok","data":[]}',
      '/api/commune' =>
        '''
        {
          "status":"ok",
          "data":{
            "communes":[
              {"id": 24091, "name": "Andilana", "district": "Antananarivo"},
              {"id": 24092, "name": "Ambatomena", "district": "Manjakandriana"}
            ]
          }
        }
      ''',
      _ => '{"status":"error","message":"route inconnue"}',
    };
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

class _MalformedMineAdapter implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final body = switch (options.path) {
      '/api/login' =>
        '{"status":"ok","data":{"token":"token","agent":{"login":"eddy","name":"Eddy"}}}',
      '/api/mine' =>
        '''
        {
          "status":"ok",
          "data":{
            "mines":[
              {
                "id": 7,
                "name": "Mine Test Sync",
                "lat": -18.89,
                "lon": 47.55,
                "radius_m": 0,
                "district": false,
                "commune": false,
                "region": false,
                "active": 1
              }
            ]
          }
        }
        ''',
      '/api/storage' => '{"status":"ok","data":[]}',
      '/api/commune' =>
        '''
        {
          "status":"ok",
          "data":{
            "communes":[
              {"id": 24091, "name":"Andilana", "district":"Antananarivo"}
            ]
          }
        }
      ''',
      _ => '{"status":"error","message":"route inconnue"}',
    };
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

void main() {
  test('le login charge mines, dépôts et communes', () async {
    final adapter = _RoutingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

    final result = await RetrofitAuthRemoteDataSource(
      AuthApi(dio),
      dio,
    ).login('eddy', 'secret');

    expect(
      adapter.paths,
      containsAll(['/api/login', '/api/mine', '/api/storage', '/api/commune']),
    );
    expect(adapter.paths, contains('/api/mine'));
    expect(adapter.paths, contains('/api/storage'));
    expect(adapter.paths, contains('/api/commune'));
    expect(result.communes, hasLength(2));
    expect(result.communes.first.id, 24091);
    expect(result.communes.first.name, 'Andilana');
  });

  test('le login tolère les champs mine textuels non conformes', () async {
    final adapter = _MalformedMineAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;

    final result = await RetrofitAuthRemoteDataSource(
      AuthApi(dio),
      dio,
    ).login('eddy', 'secret');

    expect(result.mines, hasLength(1));
    final mine = result.mines.single;
    expect(mine.id, '7');
    expect(mine.nom, 'Mine Test Sync');
    expect(mine.district, isNull);
    expect(mine.commune, isNull);
    expect(mine.region, isNull);
    expect(adapter.paths, contains('/api/commune'));
    expect(result.communes, hasLength(1));
    expect(result.communes.first.name, 'Andilana');
  });
}
