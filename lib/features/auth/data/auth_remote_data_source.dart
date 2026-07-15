import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../../sync/domain/repositories/remote_data_source.dart' show RemoteMine;

part 'auth_remote_data_source.g.dart';

class RemoteDepot {
  final String id, nom;
  final double lat, lon, rayonMetres;
  final bool actif;
  RemoteDepot(this.id, this.nom, this.lat, this.lon, this.rayonMetres,
      this.actif);
}

/// Résultat du login distant : token + agent + référentiel (mines, dépôts).
class LoginResult {
  final String token;
  final String agentId;
  final String agentNom;
  final List<RemoteMine> mines;
  final List<RemoteDepot> depots;
  LoginResult({
    required this.token,
    required this.agentId,
    required this.agentNom,
    required this.mines,
    required this.depots,
  });
}

abstract class AuthRemoteDataSource {
  /// Authentifie (identifiant + mot de passe) et renvoie token + référentiel.
  Future<LoginResult> login(String login, String password);
}

@RestApi()
abstract class AuthApi {
  factory AuthApi(Dio dio, {String baseUrl}) = _AuthApi;

  @POST('/api/geospatial/login')
  Future<dynamic> login(@Body() Map<String, dynamic> body);
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
    return LoginResult(
      token: data['token'] as String,
      agentId: (agent['login'] ?? login).toString(),
      agentNom: (agent['name'] ?? login).toString(),
      mines: _mines(data['mines'] as List?),
      depots: _depots(data['depots'] as List?),
    );
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
}

/// Mock démo : token factice + référentiel seedé.
class MockAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  Future<LoginResult> login(String login, String password) async => LoginResult(
        token: 'demo-token',
        agentId: 'F001',
        agentNom: 'Fournisseur Démo',
        mines: [
          RemoteMine('M001', 'Carrière Andilana', -18.91, 47.52, 20,
              'Ambohidratrimo', 'Andilana', 'Analamanga', true),
          RemoteMine('M002', 'Carrière Ambatomena', -18.925, 47.535, 20,
              'Manjakandriana', 'Ambatomena', 'Analamanga', true),
          RemoteMine('M003', 'Carrière Sahatany', -19.0, 47.6, 20,
              'Antsirabe II', 'Sahatany', 'Vakinankaratra', true),
        ],
        depots: [
          RemoteDepot('D001', 'Dépôt Antananarivo', -18.879, 47.5079, 20, true),
          RemoteDepot('D002', 'Dépôt Antsirabe', -19.8659, 47.0334, 20, true),
        ],
      );
}
