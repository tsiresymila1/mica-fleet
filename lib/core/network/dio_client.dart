import 'package:dio/dio.dart';

Dio buildDio({required String baseUrl, String? token}) {
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {if (token != null) 'Authorization': 'Bearer $token'},
  ));
}
