import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

part 'remote_data_source_retrofit.g.dart';

/// API Radoran (collection Postman Technarea).
@RestApi()
abstract class OdooApi {
  factory OdooApi(Dio dio, {String baseUrl}) = _OdooApi;

  @POST('/api/tracking/submit')
  Future<dynamic> submit(@Body() Map<String, dynamic> body);

  @POST('/api/mine')
  Future<dynamic> submitMine(@Body() Map<String, dynamic> body);

  @GET('/api/mine')
  Future<dynamic> mines();

  @GET('/api/storage')
  Future<dynamic> storages();

  @GET('/api/tracking/lots')
  Future<dynamic> lots();
}

class RetrofitRemoteDataSource implements RemoteDataSource {
  final OdooApi api;
  final Dio dio; // pour l'upload multipart dynamique
  RetrofitRemoteDataSource(this.api, this.dio);

  @override
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    await _uploadAttachment(deviceUuid, payloadId, photo);
  }

  @override
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    await _uploadAttachment(deviceUuid, payloadId, photo);
  }

  Future<void> _uploadAttachment(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    final form = FormData();
    form.fields.add(MapEntry('device_uuid', deviceUuid));
    form.fields.add(MapEntry('payload_id', payloadId));
    form.fields.add(MapEntry('key', photo.key));
    form.fields.add(MapEntry('hash', photo.hash));
    form.files.add(MapEntry('file', await MultipartFile.fromFile(photo.path)));
    final resp = await dio.post('/api/attachments', data: form);
    final data = resp.data;
    if (data is Map && data['status'] == 'error') {
      throw Exception(data['message'] ?? 'Échec upload photos');
    }
  }

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    final envelope = {
      'device_uuid': op.opId,
      'agent_login': op.agentLogin,
      'collected_at': _odooDate(op.createdAt),
      'payload': op.payload,
    };
    final dynamic resp;
    if (op.entityType == 'mine_submission') {
      resp = await api.submitMine(envelope);
    } else {
      resp = await api.submit({
        ...envelope,
        // Odoo attend 'chargement' : côté serveur un enregistrement = un lot.
        'collect_type': 'chargement',
        'gps_lat': op.gpsLat,
        'gps_lon': op.gpsLon,
        'gps_accuracy': op.gpsAccuracy,
      });
    }
    // Réponse uniforme : lire 'status' (pas le code HTTP).
    // created (201) et already_synced (200) = succès.
    if (resp is Map) {
      final status = resp['status'];
      if (status == 'error') {
        throw Exception(resp['message'] ?? 'Erreur serveur');
      }
      final data = resp['data'];
      if (data is Map && data['id'] != null) {
        return (data['id'] as num).toInt();
      }
    }
    return null;
  }

  @override
  Future<List<RemoteMine>> fetchMines() async {
    final mines = _requiredList(await api.mines(), 'mines');
    return mines.map((entry) => _mineFromMap(entry as Map)).toList();
  }

  @override
  Future<List<RemoteDepot>> fetchDepots() async {
    final depots = _requiredList(await api.storages(), 'depots');
    return depots.map((entry) {
      final depot = entry as Map;
      return RemoteDepot(
        depot['id'].toString(),
        depot['name'].toString(),
        (depot['lat'] as num).toDouble(),
        (depot['lon'] as num).toDouble(),
        (depot['radius_m'] as num?)?.toDouble() ?? 20,
        depot['active'] as bool? ?? true,
      );
    }).toList();
  }

  @override
  Future<List<RemoteLot>> fetchLots() async {
    final lots = _requiredList(await api.lots(), 'lots');
    final result = <RemoteLot>[];
    for (final entry in lots) {
      if (entry is! Map) continue;
      // Contrat v3 : chaque entrée est exactement `payload` du submit,
      // enrichi des trois champs serveur. `payload_id` reste toléré seulement
      // pour relire une réponse déployée avant ce contrat.
      final payloadId = (entry['id'] ?? entry['payload_id'])?.toString();
      final sessionId = entry['session_id']?.toString();
      if (payloadId == null ||
          payloadId.isEmpty ||
          sessionId == null ||
          sessionId.isEmpty) {
        continue;
      }
      final mine = entry['mine'] is Map ? entry['mine'] as Map : entry;
      final mineId = (mine['mine_id'] ?? entry['mine_id'])?.toString();
      if (mineId == null || mineId.isEmpty) continue;
      result.add(
        RemoteLot(
          payloadId: payloadId,
          sessionId: sessionId,
          reference: (entry['traceability_reference'] ?? entry['lot_reference'])
              ?.toString(),
          validationStatus: _validationStatus(
            entry['validation_status']?.toString(),
          ),
          validationReason:
              (entry['validation_reason'] ?? entry['rejection_reason'])
                  ?.toString(),
          createdAt:
              _date(entry['created_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: _date(entry['updated_at']),
          mineId: mineId,
          mineName:
              (mine['mine_name'] ?? mine['name'] ?? entry['mine_name'])
                  ?.toString() ??
              mineId,
          color: (mine['color'] ?? entry['color'])?.toString(),
          estimatedQuantity:
              (mine['estimated_quantity'] ?? entry['estimated_quantity']) is num
              ? ((mine['estimated_quantity'] ?? entry['estimated_quantity'])
                        as num)
                    .toDouble()
              : double.tryParse(
                  (mine['estimated_quantity'] ?? entry['estimated_quantity'])
                          ?.toString() ??
                      '',
                ),
          transportStatus:
              entry['status']?.toString() ??
              entry['transport_status']?.toString() ??
              'arrive',
          score: entry['traceability_score'] is num
              ? (entry['traceability_score'] as num).round()
              : int.tryParse(entry['traceability_score']?.toString() ?? ''),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await dio.post<dynamic>(
      '/api/password/change',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
    if (response.data is Map && response.data['status'] == 'error') {
      throw PasswordChangeRejected(
        response.data['message']?.toString() ?? 'Mot de passe refusé',
      );
    }
  }

  /// Tolère une liste nue, `{data: [...]}` et `{data: {<key>: [...]}}`.
  static List? _list(dynamic response, String key) {
    if (response is List) return response;
    if (response is! Map) return null;
    final data = response['data'];
    if (data is List) return data;
    if (data is Map && data[key] is List) return data[key] as List;
    return null;
  }

  static List _requiredList(dynamic response, String key) {
    if (response is Map && response['status'] == 'error') {
      throw Exception(response['message'] ?? 'Référentiel $key indisponible');
    }
    final result = _list(response, key);
    if (result == null) {
      throw FormatException('Format du référentiel $key invalide');
    }
    return result;
  }

  static RemoteMine _mineFromMap(Map m) => RemoteMine(
    m['id'].toString(),
    m['name'] as String,
    (m['lat'] as num).toDouble(),
    (m['lon'] as num).toDouble(),
    (m['radius_m'] as num?)?.toDouble() ?? 20,
    m['district'] as String?,
    m['commune'] as String?,
    m['region'] as String?,
    m['active'] as bool? ?? true,
    fokontany: m['fokontany'] as String?,
  );

  static DateTime? _date(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));

  static String _validationStatus(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'validated' || 'valide' || 'validé' => 'validated',
        'rejected' || 'rejete' || 'rejeté' => 'rejected',
        _ => 'in_progress',
      };

  /// Datetime au format Odoo : 'YYYY-MM-DD HH:MM:SS' (UTC).
  static String _odooDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
