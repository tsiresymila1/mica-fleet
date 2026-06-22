import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/fournisseur.dart';

abstract class AuthRepository {
  Future<Either<Failure, Fournisseur>> login(String identifiant);
  Future<Fournisseur?> currentSession();
}
