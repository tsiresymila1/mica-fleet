import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/fournisseur.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_ds.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthLocalDataSource local;
  AuthRepositoryImpl(this.local);

  @override
  Future<Either<Failure, Fournisseur>> login(String identifiant) async {
    final row = await local.findById(identifiant);
    if (row == null) return left(const Failure.auth('Fournisseur inconnu'));
    if (!row.actif) return left(const Failure.auth('Compte inactif'));
    await local.saveSession(row.id, row.nom);
    return right(Fournisseur(id: row.id, nom: row.nom, actif: row.actif));
  }

  @override
  Future<Fournisseur?> currentSession() async {
    final all = await local.db.select(local.db.fournisseurs).get();
    final s = all.where((f) => f.sessionToken != null).firstOrNull;
    return s == null ? null : Fournisseur(id: s.id, nom: s.nom, actif: s.actif);
  }
}
