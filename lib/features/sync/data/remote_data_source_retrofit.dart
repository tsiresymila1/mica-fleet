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
    return _mineList(
      mines
          .map((entry) => entry as Map<String, dynamic>?)
          .where((entry) => entry != null)
          .toList(),
    );
  }

  @override
  Future<List<RemoteDepot>> fetchDepots() async {
    final depots = _requiredList(await api.storages(), 'depots');
    final items = <RemoteDepot>[];
    for (final entry in depots) {
      final depot = entry as Map<String, dynamic>?;
      if (depot == null) continue;
      final lat = _toDouble(depot['lat']);
      final lon = _toDouble(depot['lon']);
      final id = depot['id']?.toString();
      final nom = _asString(depot['name']);
      if (id == null || id.isEmpty || nom == null || nom.isEmpty) continue;
      if (lat == null || lon == null) continue;
      items.add(
        RemoteDepot(
          id,
          nom,
          lat,
          lon,
          _toDouble(depot['radius_m']) ?? 20.0,
          _asBool(depot['active']) ?? true,
        ),
      );
    }
    return items;
  }

  @override
  Future<List<RemoteCommune>> fetchCommunes() async {
    final communes = _requiredList(
      await dio.get('/api/commune').then((r) => r.data),
      'communes',
    );
    final items = <RemoteCommune>[];
    for (final entry in communes) {
      final commune = entry is Map<String, dynamic> ? entry : null;
      if (commune == null) continue;
      final id = commune['id'];
      final parsedId = id is int
          ? id
          : id is String
          ? int.tryParse(id)
          : null;
      if (parsedId == null) continue;
      final name = _asOptionalString(commune['name']);
      if (name == null || name.isEmpty) continue;
      final district = _asOptionalString(commune['district']);
      items.add(
        RemoteCommune(
          id: parsedId,
          name: name,
          district: district,
          actif: _asBool(commune['active']) ?? true,
        ),
      );
    }
    return items;
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
      final arrival = entry['arrival'] is Map
          ? entry['arrival'] as Map
          : const <dynamic, dynamic>{};
      final mineId = (mine['mine_id'] ?? entry['mine_id'])?.toString();
      if (mineId == null || mineId.isEmpty) continue;
      final mineLat = _toDouble(mine['lat']);
      final mineLon = _toDouble(mine['lon']);
      result.add(
        RemoteLot(
          payloadId: payloadId,
          sessionId: sessionId,
          reference:
              _asOptionalString(entry['traceability_reference']) ??
              _asOptionalString(entry['lot_reference']),
          validationStatus: _validationStatus(
            entry['validation_status']?.toString(),
          ),
          validationReason:
              _asOptionalString(entry['validation_reason']) ??
              _asOptionalString(entry['rejection_reason']),
          createdAt:
              _date(entry['created_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: _date(entry['updated_at']),
          mineId: mineId,
          mineName:
              _asOptionalString(mine['mine_name']) ??
              _asOptionalString(mine['name']) ??
              _asOptionalString(entry['mine_name']) ??
              mineId,
          mineReference:
              _asOptionalString(mine['reference']) ??
              _asOptionalString(entry['mine_reference']),
          mineNote:
              _asOptionalString(mine['note']) ??
              _asOptionalString(entry['mine_note']) ??
              _asOptionalString(entry['note']),
          color:
              _asOptionalString(mine['color']) ??
              _asOptionalString(entry['color']),
          estimatedQuantity: _toDouble(
            mine['estimated_quantity'] ?? entry['estimated_quantity'],
          ),
          transportStatus:
              entry['status']?.toString() ??
              entry['transport_status']?.toString() ??
              'arrive',
          score: _asInt(
            entry['traceability_score'] ??
                arrival['traceability_score'] ??
                entry['score'],
          ),
          photoSchemaVersion: _asInt(entry['photo_schema_version']) ?? 3,
          minePlate: _asOptionalString(mine['plate']),
          mineLat: mineLat,
          mineLon: mineLon,
          mineGpsAccuracy: _toDouble(mine['gps_accuracy']),
          mineCapturedAt: _date(mine['captured_at']),
          minePhotos: _lotPhotos(mine['photos']),
          transloads: _transloads(entry['transloads']),
          arrival: _lotArrival(
            arrival,
            fallbackLat: mineLat,
            fallbackLon: mineLon,
          ),
          track: _track(entry['track']),
        ),
      );
    }
    return result;
  }

  static int? _asInt(dynamic value) =>
      value is num ? value.round() : int.tryParse(value?.toString() ?? '');

  static List<RemoteLotPhoto> _lotPhotos(dynamic raw) {
    if (raw is! Map) return const [];
    final photos = <RemoteLotPhoto>[];
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final role = entry.key.toString();
      photos.add(
        RemoteLotPhoto(
          role: role,
          key: _asString(value['key']) ?? role,
          url: _asOptionalString(value['url']),
          hash: _asString(value['hash']) ?? '',
          lat: _toDouble(value['lat']) ?? 0,
          lon: _toDouble(value['lon']) ?? 0,
          gpsAccuracy: _toDouble(value['gps_accuracy']) ?? 0,
          capturedAt:
              _date(value['captured_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          headingDegrees: _toDouble(value['heading_deg']),
          headingAccuracy: _toDouble(value['heading_accuracy']),
          headingReference: _asOptionalString(value['heading_reference']),
        ),
      );
    }
    return photos;
  }

  static List<RemoteTransload> _transloads(dynamic raw) {
    if (raw is! List) return const [];
    final result = <RemoteTransload>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final order = _asInt(entry['order']);
      if (order == null) continue;
      final unload = _gps(entry['gps_unload']);
      final reload = _gps(entry['gps_reload']);
      result.add(
        RemoteTransload(
          order: order,
          plateBefore: _asOptionalString(entry['plate_before']),
          plateAfter: _asOptionalString(entry['plate_after']),
          unloadLat: unload.$1,
          unloadLon: unload.$2,
          reloadLat: reload.$1,
          reloadLon: reload.$2,
          distanceMeters: _toDouble(entry['distance_m']),
          compliant: _asBool(entry['compliant']) ?? false,
          unloadPhotos: _lotPhotos(entry['photos_unload']),
          reloadPhotos: _lotPhotos(entry['photos_reload']),
        ),
      );
    }
    return result;
  }

  static RemoteLotArrival? _lotArrival(
    Map arrival, {
    required double? fallbackLat,
    required double? fallbackLon,
  }) {
    if (arrival.isEmpty) return null;
    final gps = _gps(arrival['gps']);
    final licensePhoto = arrival['photo_license'] is Map
        ? arrival['photo_license'] as Map
        : const <dynamic, dynamic>{};
    return RemoteLotArrival(
      driver: _asString(arrival['driver']) ?? '',
      licenseNumber: _asString(arrival['license_number']) ?? '',
      lat: gps.$1 ?? fallbackLat ?? 0,
      lon: gps.$2 ?? fallbackLon ?? 0,
      gpsStatus: _asString(arrival['gps_status']) ?? 'pending_server',
      plate: _asOptionalString(arrival['plate_arrival']),
      plateConsistent: _asBool(arrival['plate_consistent']) ?? false,
      score: _asInt(arrival['traceability_score']),
      licensePhotoUrl: _asOptionalString(licensePhoto['url']),
      unloadPhotos: _lotPhotos(arrival['photos_unload']),
    );
  }

  static List<RemoteTrackPoint> _track(dynamic raw) {
    if (raw is! List) return const [];
    final result = <RemoteTrackPoint>[];
    for (final point in raw) {
      if (point is! List || point.length < 3) continue;
      final lat = _toDouble(point[0]);
      final lon = _toDouble(point[1]);
      final capturedAt = _date(point[2]);
      if (lat == null || lon == null || capturedAt == null) continue;
      result.add(RemoteTrackPoint(lat: lat, lon: lon, capturedAt: capturedAt));
    }
    return result;
  }

  static (double?, double?) _gps(dynamic raw) {
    if (raw is! List || raw.length < 2) return (null, null);
    return (_toDouble(raw[0]), _toDouble(raw[1]));
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

  static RemoteMine? _mineFromMap(Map<String, dynamic> m) {
    final lat = _toDouble(m['lat']);
    final lon = _toDouble(m['lon']);
    final id = m['id']?.toString();
    final nom = _asString(m['name']);
    if (id == null || id.isEmpty || nom == null || nom.isEmpty) return null;
    if (lat == null || lon == null) return null;
    return RemoteMine(
      id,
      nom,
      lat,
      lon,
      _toDouble(m['radius_m']) ?? 20.0,
      _asOptionalString(m['district']),
      _asOptionalString(m['commune']),
      _asOptionalString(m['region']),
      _asBool(m['active']) ?? true,
      reference: _asOptionalString(m['reference']),
      note: _asOptionalString(m['note']),
      createdAt: _date(m['created_at']) ?? _date(m['createdAt']),
      fokontany: _asOptionalString(m['fokontany']),
    );
  }

  static String? _asOptionalString(dynamic value) =>
      value is String ? (value.isEmpty ? null : value) : null;

  static String? _asString(dynamic value) => switch (value) {
    String v => v.isEmpty ? null : v,
    null => null,
    _ => value.toString(),
  };

  static double? _toDouble(dynamic value) => switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v),
    _ => null,
  };

  static bool? _asBool(dynamic value) => switch (value) {
    bool v => v,
    String v => _parseBool(v),
    int v => v != 0,
    _ => null,
  };

  static bool? _parseBool(String value) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 't':
      case 'yes':
      case 'y':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'f':
      case 'no':
      case 'n':
      case 'off':
        return false;
      default:
        return null;
    }
  }

  static List<RemoteMine> _mineList(List? raw) {
    if (raw == null) return [];
    final mines = <RemoteMine>[];
    for (final entry in raw) {
      final map = entry is Map<String, dynamic> ? entry : null;
      if (map == null) continue;
      final mine = _mineFromMap(map);
      if (mine != null) {
        mines.add(mine);
      }
    }
    return mines;
  }

  static DateTime? _date(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));

  static String _validationStatus(String? value) =>
      switch (value?.trim().toLowerCase()) {
        'pending' => 'pending',
        'draft' => 'pending',
        'validated' || 'valide' || 'validé' => 'validated',
        'rejected' || 'rejete' || 'rejeté' => 'rejected',
        _ => 'pending',
      };

  /// Datetime au format Odoo : 'YYYY-MM-DD HH:MM:SS' (UTC).
  static String _odooDate(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
