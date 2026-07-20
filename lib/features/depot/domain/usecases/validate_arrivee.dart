import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../entities/arrivee_depot.dart';
import '../entities/depot.dart';
import 'detect_depot.dart';

class ValidateArrivee {
  final DetectDepot detect;
  ValidateArrivee(this.detect);

  Either<Failure, ArriveeDepot> call({
    required String lotId,
    required List<Depot> depots,
    required double lat,
    required double lon,
    required String chauffeur,
    required String numPermis,
    required String numLot,
    String? plaqueArrivee,
    String? plaqueAttendue, // dernière plaque connue de CE lot
    String? photoArriveePath,
    String? photoPermisPath,
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
      lotId: lotId,
      depotId: depot.id,
      chauffeur: chauffeur,
      numPermis: numPermis,
      numLot: numLot,
      gpsLat: lat,
      gpsLon: lon,
      statutGps: 'valide',
      plaqueArrivee: plaqueArrivee,
      plaqueCoherente: _coherente(plaqueArrivee, plaqueAttendue),
      photoArriveePath: photoArriveePath,
      photoPermisPath: photoPermisPath,
    ));
  }

  /// Vrai si plaque d'arrivée == plaque attendue (anti-fraude immatriculation).
  /// Si l'une est inconnue, on ne peut pas infirmer → cohérent.
  bool _coherente(String? arrivee, String? attendue) {
    if (arrivee == null || attendue == null) return true;
    String norm(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return norm(arrivee) == norm(attendue);
  }
}
