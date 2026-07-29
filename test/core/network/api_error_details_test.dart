import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/network/api_error_details.dart';

void main() {
  test('une réponse HTTP expose le code, la route et le JSON serveur', () {
    final request = RequestOptions(
      path: '/api/tracking/submit',
      method: 'POST',
    );
    final error = DioException.badResponse(
      statusCode: 500,
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: 500,
        data: {
          'status': 'error',
          'message': 'Odoo Server Error',
          'detail': 'Le payload_id existe déjà',
        },
      ),
    );

    final details = apiErrorDetails(error);

    expect(details, contains('HTTP 500'));
    expect(details, contains('POST /api/tracking/submit'));
    expect(details, contains('Odoo Server Error'));
    expect(details, contains('Le payload_id existe déjà'));
    expect(details, isNot(contains('validateStatus')));
  });

  test('une erreur réseau sans réponse donne une explication lisible', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/api/attachments', method: 'POST'),
      type: DioExceptionType.connectionTimeout,
      message: 'The request connection took longer than 0:00:15',
    );

    final details = apiErrorDetails(error);

    expect(details, contains('Délai de connexion dépassé'));
    expect(details, contains('POST /api/attachments'));
  });

  test('le détail stocké est borné pour protéger la base locale', () {
    final request = RequestOptions(path: '/api/tracking/submit');
    final error = DioException.badResponse(
      statusCode: 500,
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: 500,
        data: {'debug': 'x' * 10000},
      ),
    );

    expect(apiErrorDetails(error).length, lessThanOrEqualTo(6000));
  });
}
