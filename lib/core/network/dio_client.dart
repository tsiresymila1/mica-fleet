import 'package:dio/dio.dart';

/// Construit le client dio. [tokenReader] fournit le Bearer token (lu de façon
/// chiffrée) et est appelé à chaque requête → rotation possible sans rebuild.
Dio buildDio({
  required String baseUrl,
  Future<String?> Function()? tokenReader,
}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
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
  return dio;
}
