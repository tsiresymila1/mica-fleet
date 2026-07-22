import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Construit le client dio. [tokenReader] fournit le Bearer token (lu de façon
/// chiffrée) et est appelé à chaque requête → rotation possible sans rebuild.
Dio buildDio({
  required String baseUrl,
  Future<String?> Function()? tokenReader,
}) {
  final dio = Dio(BaseOptions(
    // Les chemins commencent par '/api/…' : un slash final collerait un
    // double '//' au milieu de l'URL.
    baseUrl: baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  if (tokenReader != null) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await tokenReader();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));
  }
  // Trace les appels en debug pour diagnostiquer un serveur réel (URL, code,
  // message d'erreur). Jamais en release : les payloads contiennent des GPS.
  if (kDebugMode) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        debugPrint('→ ${o.method} ${o.uri} ${o.data}');
        h.next(o);
      },
      onResponse: (r, h) {
        debugPrint('← ${r.statusCode} ${r.requestOptions.uri} ${r.data}');
        h.next(r);
      },
      onError: (e, h) {
        debugPrint('✗ ${e.response?.statusCode ?? e.type} '
            '${e.requestOptions.uri} : ${e.response?.data ?? e.message}');
        h.next(e);
      },
    ));
  }
  return dio;
}
