import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/transbordement.dart';

abstract class TransportRepository {
  /// Remplace la chaîne de transbordements d'un chargement et journalise la sync.
  Future<Either<Failure, Unit>> persistChaine(
      String chargementId, List<Transbordement> chaine);

  Future<List<Transbordement>> chaineFor(String chargementId);
}
