import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:retrofit/retrofit.dart';
import '../../sync/domain/repositories/remote_data_source.dart'
    show RemoteCommune, RemoteDepot, RemoteMine;

part 'auth_remote_data_source.g.dart';

/// Résultat du login distant : token + agent + référentiels locaux.
class LoginResult {
  final String token;
  final String agentId;
  final String agentNom;
  final List<RemoteMine> mines;
  final List<RemoteCommune> communes;
  final List<RemoteDepot> depots;
  LoginResult({
    required this.token,
    required this.agentId,
    required this.agentNom,
    required this.mines,
    required this.communes,
    required this.depots,
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
}

class RetrofitAuthRemoteDataSource implements AuthRemoteDataSource {
  final AuthApi api;
  final Dio dio;
  RetrofitAuthRemoteDataSource(this.api, this.dio);

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
      communes: _communes(
        await _tryList(
          () async => _listFromResponse(
            await dio.get(
              '/api/commune',
              options: Options(headers: {'Authorization': bearer}),
            ),
          ),
          'communes',
        ),
      ),
      depots: _depots(await _tryList(() => api.storages(bearer), 'depots')),
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

  List? _listFromResponse(Response<dynamic> response) {
    return _list(response.data, 'communes');
  }

  List<RemoteCommune> _communes(List? raw) {
    if (raw == null) return [];
    final communes = <RemoteCommune>[];
    for (final entry in raw) {
      final m = entry as Map<String, dynamic>?;
      if (m == null) continue;
      final id = m['id'];
      final communeId = id is int
          ? id
          : id is String
          ? int.tryParse(id)
          : null;
      final name = _asOptionalString(m['name']);
      if (communeId == null || name == null || name.isEmpty) continue;
      communes.add(
        RemoteCommune(
          id: communeId,
          name: name,
          district: _asOptionalString(m['district']),
          actif: _asBool(m['active']) ?? true,
        ),
      );
    }
    return communes;
  }

  List<RemoteMine> _mines(List? raw) {
    if (raw == null) return [];
    final mines = <RemoteMine>[];
    for (final entry in raw) {
      final m = entry as Map<String, dynamic>?;
      if (m == null) continue;
      final lat = _toDouble(m['lat']);
      final lon = _toDouble(m['lon']);
      final id = m['id']?.toString();
      final nom = _asString(m['name']);
      if (id == null || id.isEmpty || nom == null || nom.isEmpty) continue;
      if (lat == null || lon == null) continue;
      mines.add(
        RemoteMine(
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
          createdAt: _parseDate(m['created_at']) ?? _parseDate(m['createdAt']),
          fokontany: _asOptionalString(m['fokontany']),
        ),
      );
    }
    return mines;
  }

  List<RemoteDepot> _depots(List? raw) {
    if (raw == null) return [];
    final depots = <RemoteDepot>[];
    for (final entry in raw) {
      final d = entry as Map<String, dynamic>?;
      if (d == null) continue;
      final lat = _toDouble(d['lat']);
      final lon = _toDouble(d['lon']);
      final id = d['id']?.toString();
      final nom = _asString(d['name']);
      if (id == null || id.isEmpty || nom == null || nom.isEmpty) continue;
      if (lat == null || lon == null) continue;
      depots.add(
        RemoteDepot(
          id,
          nom,
          lat,
          lon,
          _toDouble(d['radius_m']) ?? 20.0,
          _asBool(d['active']) ?? true,
        ),
      );
    }
    return depots;
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

  static DateTime? _parseDate(dynamic value) => value == null
      ? null
      : DateTime.tryParse(value.toString().replaceFirst(' ', 'T'));
}

/// Mock démo : token factice + référentiel seedé.
class MockAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  Future<LoginResult> login(String login, String password) async => LoginResult(
    token: 'demo-token',
    agentId: 'F001',
    agentNom: 'Fournisseur Démo',
    communes: const [
      RemoteCommune(
        id: 24091,
        name: 'Andilana',
        district: 'Ambohidratrimo',
        actif: true,
      ),
      RemoteCommune(
        id: 24092,
        name: 'Ambatomena',
        district: 'Manjakandriana',
        actif: true,
      ),
      RemoteCommune(
        id: 24093,
        name: 'Sahatany',
        district: 'Antsirabe II',
        actif: true,
      ),
    ],
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
        reference: null,
        note: null,
        createdAt: DateTime(2026, 1, 1),
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
        reference: null,
        note: null,
        createdAt: DateTime(2026, 1, 1),
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
        reference: null,
        note: null,
        createdAt: DateTime(2026, 1, 1),
      ),
    ],
    depots: [
      RemoteDepot('D001', 'Dépôt Antananarivo', -18.879, 47.5079, 20, true),
      RemoteDepot('D002', 'Dépôt Antsirabe', -19.8659, 47.0334, 20, true),
    ],
  );
}
