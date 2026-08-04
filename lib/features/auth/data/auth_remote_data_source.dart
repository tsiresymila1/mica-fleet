import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:retrofit/retrofit.dart';
import '../../sync/domain/repositories/remote_data_source.dart' show RemoteMine;

part 'auth_remote_data_source.g.dart';

class RemoteDepot {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final bool actif;
  RemoteDepot(
    this.id,
    this.nom,
    this.lat,
    this.lon,
    this.rayonMetres,
    this.actif,
  );
}

class RemoteCommune {
  final int id;
  final String nom;
  final String? district;
  final bool actif;

  const RemoteCommune(this.id, this.nom, this.district, this.actif);
}

/// Résultat du login distant : token + agent + référentiels locaux.
class LoginResult {
  final String token;
  final String agentId;
  final String agentNom;
  final List<RemoteMine> mines;
  final List<RemoteDepot> depots;
  final List<RemoteCommune> communes;
  LoginResult({
    required this.token,
    required this.agentId,
    required this.agentNom,
    required this.mines,
    required this.depots,
    required this.communes,
  });
}

abstract class AuthRemoteDataSource {
  /// Authentifie (identifiant + mot de passe) et renvoie token + référentiel.
  Future<LoginResult> login(String login, String password);
}

/// API Radoran (collection Postman Technarea).
@RestApi()
abstract class AuthApi {
  factory AuthApi(Dio dio, {String baseUrl}) = _AuthApi;

  @POST('/api/login')
  Future<dynamic> login(@Body() Map<String, dynamic> body);

  /// Mines autorisées pour l'agent connecté.
  @GET('/api/mine')
  Future<dynamic> mines(@Header('Authorization') String bearer);

  /// Dépôts (storage) autorisés pour l'agent connecté.
  @GET('/api/storage')
  Future<dynamic> storages(@Header('Authorization') String bearer);

  /// Communes proposées dans le formulaire de création manuelle d'une mine.
  @GET('/api/commune')
  Future<dynamic> communes(@Header('Authorization') String bearer);
}

class RetrofitAuthRemoteDataSource implements AuthRemoteDataSource {
  final AuthApi api;
  RetrofitAuthRemoteDataSource(this.api);

  @override
  Future<LoginResult> login(String login, String password) async {
    final resp = await api.login({'login': login, 'password': password});
    if (resp is! Map || resp['status'] == 'error') {
      throw Exception(resp is Map ? resp['message'] : 'Échec login');
    }
    final data = resp['data'] as Map;
    final agent = (data['agent'] as Map?) ?? const {};
    final token = data['token'] as String;

    // Le login réussit dès qu'on a token + agent. Le référentiel (mines,
    // dépôts, communes) est servi par des endpoints séparés : on les charge en
    // best-effort — un 404/500 côté serveur ne doit PAS empêcher de se
    // connecter (l'app garde le dernier référentiel connu).
    final bearer = 'Bearer $token';
    return LoginResult(
      token: token,
      agentId: (agent['login'] ?? login).toString(),
      agentNom: (agent['name'] ?? login).toString(),
      mines: _mines(await _tryList(() => api.mines(bearer), 'mines')),
      depots: _depots(await _tryList(() => api.storages(bearer), 'depots')),
      communes: _communes(
        await _tryList(() => api.communes(bearer), 'communes'),
      ),
    );
  }

  /// Appelle un endpoint de référentiel sans faire échouer le login s'il tombe.
  Future<List?> _tryList(Future<dynamic> Function() call, String cle) async {
    try {
      return _list(await call(), cle);
    } catch (e) {
      debugPrint('Référentiel « $cle » indisponible au login : $e');
      return null;
    }
  }

  /// Tolère `{data: [...]}`, `{data: {<cle>: [...]}}` ou une liste nue.
  static List? _list(dynamic resp, String cle) {
    if (resp is List) return resp;
    if (resp is! Map) return null;
    final data = resp['data'];
    if (data is List) return data;
    if (data is Map) return data[cle] as List?;
    return null;
  }

  List<RemoteMine> _mines(List? raw) {
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return RemoteMine(
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
    }).toList();
  }

  List<RemoteDepot> _depots(List? raw) {
    if (raw == null) return [];
    return raw.map((e) {
      final d = e as Map<String, dynamic>;
      return RemoteDepot(
        d['id'].toString(),
        d['name'] as String,
        (d['lat'] as num).toDouble(),
        (d['lon'] as num).toDouble(),
        (d['radius_m'] as num?)?.toDouble() ?? 20,
        d['active'] as bool? ?? true,
      );
    }).toList();
  }

  List<RemoteCommune> _communes(List? raw) {
    if (raw == null) return [];
    final result = <RemoteCommune>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final commune = Map<String, dynamic>.from(entry);
      final rawId = commune['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      final nom = (commune['name'] ?? commune['nom'])?.toString().trim();
      if (id == null || nom == null || nom.isEmpty) continue;
      final rawDistrict = commune['district'];
      final district = rawDistrict is Map
          ? (rawDistrict['name'] ?? rawDistrict['nom'])?.toString()
          : rawDistrict?.toString();
      final rawActive = commune['active'];
      result.add(
        RemoteCommune(
          id,
          nom,
          district,
          rawActive is bool
              ? rawActive
              : rawActive == null ||
                    rawActive.toString() == '1' ||
                    rawActive.toString().toLowerCase() == 'true',
        ),
      );
    }
    return result;
  }
}

/// Mock démo : token factice + référentiel seedé.
class MockAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  Future<LoginResult> login(String login, String password) async => LoginResult(
    token: 'demo-token',
    agentId: 'F001',
    agentNom: 'Fournisseur Démo',
    mines: [
      RemoteMine(
        'M001',
        'Carrière Andilana',
        -18.91,
        47.52,
        20,
        'Ambohidratrimo',
        'Andilana',
        'Analamanga',
        true,
      ),
      RemoteMine(
        'M002',
        'Carrière Ambatomena',
        -18.925,
        47.535,
        20,
        'Manjakandriana',
        'Ambatomena',
        'Analamanga',
        true,
      ),
      RemoteMine(
        'M003',
        'Carrière Sahatany',
        -19.0,
        47.6,
        20,
        'Antsirabe II',
        'Sahatany',
        'Vakinankaratra',
        true,
      ),
    ],
    depots: [
      RemoteDepot('D001', 'Dépôt Antananarivo', -18.879, 47.5079, 20, true),
      RemoteDepot('D002', 'Dépôt Antsirabe', -19.8659, 47.0334, 20, true),
    ],
    communes: const [
      RemoteCommune(24091, 'Andilana', 'Ambohidratrimo', true),
      RemoteCommune(24092, 'Ambatomena', 'Manjakandriana', true),
      RemoteCommune(24093, 'Sahatany', 'Antsirabe II', true),
    ],
  );
}
