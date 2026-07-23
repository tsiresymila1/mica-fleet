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
    // On rattache au dépôt le plus proche sans exiger d'être dans la zone :
    // hors zone ou coords serveur absentes n'empêchent plus de valider — le
    // statutGps le reflète et le score en tient compte. Seul un référentiel
    // sans aucun dépôt bloque (rien à rattacher).
    final proche = detect.nearest(depots, lat, lon);
    if (proche == null) {
      return left(const Failure.validation('Aucun dépôt dans le référentiel'));
    }
    return right(ArriveeDepot(
      lotId: lotId,
      depotId: proche.depot.id,
      chauffeur: chauffeur,
      numPermis: numPermis,
      numLot: numLot,
      gpsLat: lat,
      gpsLon: lon,
      statutGps: proche.statutGps,
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
