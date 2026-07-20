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
  String? couleur,
});

abstract class DepotRepository {
  Future<List<Depot>> activeDepots();

  /// Enregistre l'arrivée d'UN lot et journalise la sync.
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot arrivee);

  /// Infos du lot : session, mine, date, plaque de départ, couleur.
  Future<LotResume?> lotResume(String lotId);

  /// Lots d'une session encore en cours (non arrivés).
  Future<List<({String id, String mineId, String? couleur})>> lotsEnCours(
      String sessionId);
}
