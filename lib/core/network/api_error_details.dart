import 'dart:convert';

import 'package:dio/dio.dart';

const _maxStoredErrorLength = 6000;

/// Transforme une erreur réseau en diagnostic exploitable dans le rapport de
/// synchronisation. Les headers et le corps de la requête ne sont jamais
/// inclus afin de ne pas stocker le Bearer token ni les données terrain.
String apiErrorDetails(Object error) {
  final details = error is DioException
      ? _dioDetails(error)
      : error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (details.length <= _maxStoredErrorLength) return details;
  return '${details.substring(0, _maxStoredErrorLength - 1)}…';
}

String _dioDetails(DioException error) {
  final request = error.requestOptions;
  final route = '${request.method.toUpperCase()} ${request.uri.path}';
  final response = error.response;
  if (response != null) {
    final status = response.statusCode?.toString() ?? 'inconnu';
    final body = _responseBody(response.data);
    final fallback = response.statusMessage?.trim();
    final detail =
        body ??
        (fallback != null && fallback.isNotEmpty
            ? fallback
            : 'Le serveur n’a fourni aucun détail.');
    return 'HTTP $status · $route\n$detail';
  }

  final label = switch (error.type) {
    DioExceptionType.connectionTimeout => 'Délai de connexion dépassé',
    DioExceptionType.sendTimeout => 'Délai d’envoi dépassé',
    DioExceptionType.receiveTimeout => 'Délai de réponse dépassé',
    DioExceptionType.badCertificate => 'Certificat serveur invalide',
    DioExceptionType.cancel => 'Requête annulée',
    DioExceptionType.connectionError => 'Connexion au serveur impossible',
    DioExceptionType.badResponse => 'Réponse HTTP invalide',
    DioExceptionType.unknown => 'Erreur réseau inattendue',
  };
  final message = error.message?.trim();
  return [
    '$label · $route',
    if (message != null && message.isNotEmpty) message,
  ].join('\n');
}

String? _responseBody(dynamic data) {
  if (data == null) return null;
  if (data is String) {
    final value = data.trim();
    return value.isEmpty ? null : value;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    final value = data.toString().trim();
    return value.isEmpty ? null : value;
  }
}
