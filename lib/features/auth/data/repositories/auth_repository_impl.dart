import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/token_store.dart';
import '../../domain/entities/fournisseur.dart';
import '../../../sync/domain/repositories/remote_data_source.dart'
    show RemoteMine;
import '../../domain/repositories/auth_repository.dart';
import '../auth_remote_data_source.dart';
import '../datasources/auth_local_ds.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthLocalDataSource local;
  final AuthRemoteDataSource remote;
  final SecureTokenStore tokenStore;
  AuthRepositoryImpl(this.local, this.remote, this.tokenStore);

  @override
  Future<Either<Failure, Fournisseur>> login(
      String identifiant, String password) async {
    if (identifiant.trim().isEmpty || password.isEmpty) {
      return left(const Failure.validation('Identifiant et mot de passe requis'));
    }
    try {
      final r = await remote.login(identifiant.trim(), password);
      await tokenStore.save(r.token);
      await _upsertReferentiel(r.mines, r.depots);
      await local.saveSession(r.agentId, r.agentNom);
      return right(Fournisseur(id: r.agentId, nom: r.agentNom));
    } on DioException catch (e) {
      // 401 = mauvais identifiants : inutile de replier sur le hors ligne.
      if (e.response?.statusCode == 401) {
        return left(const Failure.auth('Identifiant ou mot de passe incorrect'));
      }
      // Autre erreur serveur/réseau : replie sur une session déjà établie.
      final offline = await _sessionHorsLigne(identifiant.trim());
      if (offline != null) return right(offline);
      final code = e.response?.statusCode;
      return left(Failure.network(code != null
          ? 'Serveur injoignable (HTTP $code sur ${e.requestOptions.path})'
          : 'Serveur injoignable — vérifie l\'adresse et le réseau'));
    } catch (e) {
      final offline = await _sessionHorsLigne(identifiant.trim());
      if (offline != null) return right(offline);
      return left(const Failure.network(
          'Connexion impossible et aucune session hors ligne'));
    }
  }

  /// Session déjà établie pour cet identifiant (repli hors ligne), ou null.
  Future<Fournisseur?> _sessionHorsLigne(String identifiant) async {
    final row = await local.findById(identifiant);
    final token = await tokenStore.read();
    if (row != null && row.actif && token != null) {
      return Fournisseur(id: row.id, nom: row.nom, actif: row.actif);
    }
    return null;
  }

  Future<void> _upsertReferentiel(
      List<RemoteMine> mines, List<RemoteDepot> depots) async {
    final db = local.db;
    await db.batch((b) {
      for (final m in mines) {
        b.insert(
          db.mines,
          MinesCompanion.insert(
            id: m.id,
            nom: m.nom,
            lat: m.lat,
            lon: m.lon,
            rayonMetres: Value(m.rayonMetres),
            district: Value(m.district),
            commune: Value(m.commune),
            region: Value(m.region),
            actif: Value(m.actif),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
      for (final d in depots) {
        b.insert(
          db.depots,
          DepotsCompanion.insert(
            id: d.id,
            nom: d.nom,
            lat: d.lat,
            lon: d.lon,
            rayonMetres: Value(d.rayonMetres),
            actif: Value(d.actif),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<Fournisseur?> currentSession() async {
    final all = await local.db.select(local.db.fournisseurs).get();
    final s = all.where((f) => f.sessionToken != null).firstOrNull;
    return s == null ? null : Fournisseur(id: s.id, nom: s.nom, actif: s.actif);
  }
}
