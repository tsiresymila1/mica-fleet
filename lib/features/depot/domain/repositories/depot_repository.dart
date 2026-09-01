import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';

/// Résumé d'un LOT utile au scoring / cohérence de plaque à l'arrivée.
typedef LotResume = ({
  String sessionId,
  String mineId,
  DateTime? cree,
  String? plaqueDepart,
});

abstract class DepotRepository {
  Future<List<Depot>> activeDepots();

  /// Enregistre l'arrivée d'UN lot et journalise la sync.
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot arrivee);

  /// Infos du lot : session, mine, date et plaque de départ.
  Future<LotResume?> lotResume(String lotId);

  Future<int> photoSchemaVersionForLot(String lotId);

  /// Lots d'une session encore en cours (non arrivés).
  Future<List<({String id, String mineId})>> lotsEnCours(String sessionId);
}
