import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';

abstract class DepotRepository {
  Future<List<Depot>> activeDepots();

  /// Enregistre l'arrivée au dépôt et journalise la sync.
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot arrivee);
}
