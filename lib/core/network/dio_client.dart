import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Construit le client dio. [tokenReader] fournit le Bearer token (lu de façon
/// chiffrée) et est appelé à chaque requête → rotation possible sans rebuild.
Dio buildDio({
  required String baseUrl,
  Future<String?> Function()? tokenReader,
}) {
  final dio = Dio(
    BaseOptions(
      // Les chemins commencent par '/api/…' : un slash final collerait un
      // double '//' au milieu de l'URL.
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  if (tokenReader != null) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenReader();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }
  // Trace les appels en debug pour diagnostiquer un serveur réel (URL, code,
  // message d'erreur). Jamais en release : les payloads contiennent des GPS.
  if (kDebugMode) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          debugPrint('→ ${o.method} ${_safeUri(o.uri)} ${o.data}');
          h.next(o);
        },
        onResponse: (r, h) {
          debugPrint(
            '← ${r.statusCode} ${_safeUri(r.requestOptions.uri)} ${r.data}',
          );
          h.next(r);
        },
        onError: (e, h) {
          debugPrint(
            '✗ ${e.response?.statusCode ?? e.type} '
            '${_safeUri(e.requestOptions.uri)} : '
            '${e.response?.data ?? e.message}',
          );
          h.next(e);
        },
      ),
    );
  }
  return dio;
}

Uri _safeUri(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri;
  final redacted = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    final key = entry.key.toLowerCase();
    redacted[entry.key] = key.contains('token') ? '***' : entry.value;
  }
  return uri.replace(queryParameters: redacted);
}
