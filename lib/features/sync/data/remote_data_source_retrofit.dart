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

  @GET('/api/commune')
  Future<dynamic> communes();
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
  Future<List<RemoteCommune>> fetchCommunes() async {
    final communes = _requiredList(await api.communes(), 'communes');
    final result = <RemoteCommune>[];
    for (final entry in communes) {
      if (entry is! Map) continue;
      final id = entry['id'] is int
          ? entry['id'] as int
          : int.tryParse(entry['id']?.toString() ?? '');
      final nom = entry['name']?.toString().trim();
      if (id == null || nom == null || nom.isEmpty) continue;
      result.add(
        RemoteCommune(
          id,
          nom,
          entry['district']?.toString(),
          entry['active'] as bool? ?? true,
        ),
      );
    }
    return result;
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
  );

  /// Datetime au format Odoo : 'YYYY-MM-DD HH:MM:SS' (UTC).
  static String _odooDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
