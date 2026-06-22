import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';
import '../repositories/auth_repository.dart';

class Login {
  final AuthRepository repo;
  Login(this.repo);

  Future<Either<Failure, Fournisseur>> call(String identifiant) {
    if (identifiant.trim().isEmpty) {
      return Future.value(left(const Failure.validation('Identifiant requis')));
    }
    return repo.login(identifiant.trim());
  }
}
