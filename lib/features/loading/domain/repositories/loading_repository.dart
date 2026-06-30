import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/chargement.dart';

abstract class LoadingRepository {
  /// Prochaine séquence annuelle pour l'ID MICA-YYYY-XXXX.
  Future<int> nextSequence(int year);
  Future<Either<Failure, Chargement>> persist(Chargement c);

  /// Supprime un chargement non finalisé (sans arrivée) et ses données liées.
  Future<Either<Failure, Unit>> deleteChargement(String chargementId);
}
