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

  @POST('/api/mine/submit')
  Future<dynamic> submitMine(@Body() Map<String, dynamic> body);

  @GET('/api/mine/submissions/{payloadId}')
  Future<dynamic> mineSubmissionStatus(@Path('payloadId') String payloadId);

  @GET('/api/mine')
  Future<dynamic> mines();
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
    await _uploadAttachment(deviceUuid, payloadId, photo, entityType: 'mine');
  }

  Future<void> _uploadAttachment(
    String deviceUuid,
    String payloadId,
    PhotoPart photo, {
    String? entityType,
  }) async {
    final form = FormData();
    if (entityType != null) {
      form.fields.add(MapEntry('entity_type', entityType));
    }
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
  Future<RemoteMineSubmissionStatus> fetchMineSubmissionStatus(
    String payloadId,
  ) async {
    final resp = await api.mineSubmissionStatus(payloadId);
    if (resp is Map && resp['status'] == 'error') {
      throw Exception(resp['message'] ?? 'Erreur de validation de la mine');
    }
    final data = resp is Map ? resp['data'] : null;
    if (data is! Map) {
      throw const FormatException('Réponse de validation mine invalide');
    }
    final mineData = data['mine'];
    return RemoteMineSubmissionStatus(
      payloadId: (data['payload_id'] ?? payloadId).toString(),
      state: (data['state'] ?? 'pending_validation').toString(),
      rejectionReason: data['rejection_reason']?.toString(),
      mine: mineData is Map ? _mineFromMap(mineData) : null,
    );
  }

  @override
  Future<List<RemoteMine>> fetchMines() async {
    final resp = await api.mines();
    List? mines;
    if (resp is List) {
      mines = resp;
    } else if (resp is Map) {
      final data = resp['data'];
      mines = data is List
          ? data
          : (data is Map ? data['mines'] as List? : null);
    }
    if (mines == null) return [];
    return mines.map((e) {
      return _mineFromMap(e as Map);
    }).toList();
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
  );

  /// Datetime au format Odoo : 'YYYY-MM-DD HH:MM:SS' (UTC).
  static String _odooDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
