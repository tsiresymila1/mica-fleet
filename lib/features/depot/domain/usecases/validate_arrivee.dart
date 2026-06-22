import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';
import 'detect_depot.dart';

class ValidateArrivee {
  final DetectDepot detect;
  ValidateArrivee(this.detect);

  Either<Failure, ArriveeDepot> call({
    required String chargementId,
    required List<Depot> depots,
    required double lat,
    required double lon,
    required String chauffeur,
    required String numPermis,
    required String numLot,
  }) {
    if (chauffeur.trim().isEmpty ||
        numPermis.trim().isEmpty ||
        numLot.trim().isEmpty) {
      return left(
          const Failure.validation('Chauffeur, permis et lot obligatoires'));
    }
    final depot = detect(depots, lat, lon);
    if (depot == null) {
      return left(
          const Failure.validation('Aucun dépôt reconnu dans la zone GPS'));
    }
    return right(ArriveeDepot(
      chargementId: chargementId,
      depotId: depot.id,
      chauffeur: chauffeur,
      numPermis: numPermis,
      numLot: numLot,
      gpsLat: lat,
      gpsLon: lon,
      statutGps: 'valide',
    ));
  }
}
