import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';

/// Résumé d'un chargement utile au scoring/cohérence à l'arrivée.
typedef ChargementResume = ({
  int nbMines,
  DateTime? cree,
  String? plaque,
  List<String> couleurs,
});

abstract class DepotRepository {
  Future<List<Depot>> activeDepots();

  /// Enregistre l'arrivée au dépôt et journalise la sync.
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot arrivee);

  /// Infos du chargement : nb mines, date création, plaque de la 1re mine.
  Future<ChargementResume> chargementResume(String chargementId);
}
