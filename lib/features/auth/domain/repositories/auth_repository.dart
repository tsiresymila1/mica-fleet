import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';

abstract class AuthRepository {
  /// Login distant (identifiant + mot de passe) : stocke le token, met à jour
  /// le référentiel mines/dépôts, cache la session. Repli hors ligne sur une
  /// session déjà établie.
  Future<Either<Failure, Fournisseur>> login(
      String identifiant, String password);
  Future<Fournisseur?> currentSession();
}
