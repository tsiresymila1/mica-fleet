import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';

abstract class AuthRepository {
  /// Login distant (identifiant + mot de passe) : stocke le token, met à jour
  /// les référentiels mines/dépôts/communes, puis cache la session. Repli hors
  /// ligne sur une session déjà établie.
  Future<Either<Failure, Fournisseur>> login(
    String identifiant,
    String password,
  );
  Future<Fournisseur?> currentSession();
  Future<void> logout();

  /// Tente une reconnexion silencieuse depuis les identifiants locaux afin de
  /// remettre un token à jour (utile au retour réseau).
  Future<bool> refreshFromStoredPassword(String login);

  /// Retourne `true` quand le changement a été mis en attente hors ligne.
  Future<Either<Failure, bool>> changePassword({
    required String login,
    required String currentPassword,
    required String newPassword,
  });
}
