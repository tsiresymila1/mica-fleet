import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/remote_data_source.dart';

part 'remote_data_source_retrofit.g.dart';

/// Contrat du module Odoo `terrain_api` (Technarea).
@RestApi()
abstract class OdooApi {
  factory OdooApi(Dio dio, {String baseUrl}) = _OdooApi;

  @POST('/api/terrain/submit')
  Future<dynamic> submit(@Body() Map<String, dynamic> body);

  @GET('/api/terrain/config')
  Future<dynamic> config();

  @GET('/api/terrain/status/{id}')
  Future<dynamic> status(@Path('id') int id);
}

class RetrofitRemoteDataSource implements RemoteDataSource {
  final OdooApi api;
  final Dio dio; // pour l'upload multipart dynamique
  RetrofitRemoteDataSource(this.api, this.dio);

  @override
  Future<void> uploadPhotos(String deviceUuid, List<PhotoPart> photos) async {
    if (photos.isEmpty) return;
    final form = FormData();
    form.fields.add(MapEntry('device_uuid', deviceUuid));
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      form.fields.add(MapEntry('photos[$i][key]', p.key));
      if (p.hash != null) {
        form.fields.add(MapEntry('photos[$i][hash]', p.hash!));
      }
      form.files.add(MapEntry(
          'photos[$i][file]', await MultipartFile.fromFile(p.path)));
    }
    final resp = await dio.post('/api/terrain/upload', data: form);
    final data = resp.data;
    if (data is Map && data['status'] == 'error') {
      throw Exception(data['message'] ?? 'Échec upload photos');
    }
  }

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    final resp = await api.submit({
      'device_uuid': op.opId, // idempotence (UNIQUE côté Odoo)
      'agent_login': op.agentLogin,
      'collected_at': _odooDate(op.createdAt),
      'collecte_type': op.entityType,
      'gps_lat': op.gpsLat,
      'gps_lon': op.gpsLon,
      'gps_accuracy': op.gpsAccuracy,
      'payload': op.payload,
    });
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
    // Le module terrain_api générique renvoie agents + types dans /config.
    // Le référentiel mines/dépôts mica est à confirmer avec Technarea
    // (endpoint dédié ou extension de /config → data.mines).
    final resp = await api.config();
    List? mines;
    if (resp is Map) {
      final data = resp['data'];
      if (data is Map) mines = data['mines'] as List?;
    }
    if (mines == null) return [];
    return mines.map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteMine(
        m['id'].toString(),
        m['nom'] as String,
        (m['lat'] as num).toDouble(),
        (m['lon'] as num).toDouble(),
        (m['rayon_metres'] as num?)?.toDouble() ?? 20,
        m['district'] as String?,
        m['commune'] as String?,
        m['region'] as String?,
        m['actif'] as bool? ?? true,
      );
    }).toList();
  }

  /// Datetime au format Odoo : 'YYYY-MM-DD HH:MM:SS' (UTC).
  static String _odooDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
