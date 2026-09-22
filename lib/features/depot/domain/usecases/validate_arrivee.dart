import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../../../capture/domain/entities/traceability_photos.dart';
import '../entities/arrivee_depot.dart';

class ValidateArrivee {
  Either<Failure, ArriveeDepot> call({
    required String lotId,
    required double lat,
    required double lon,
    required String chauffeur,
    required String numPermis,
    required String numLot,
    String? plaqueArrivee,
    String? plaqueAttendue, // dernière plaque connue de CE lot
    TraceabilityPhotos? photosDecharge,
    String? photoArriveePath,
    double? photoArriveeHeadingDegrees,
    double? photoArriveeHeadingAccuracy,
    String? photoArriveeHeadingReference,
    String? photoPermisPath,
    double? photoPermisHeadingDegrees,
    double? photoPermisHeadingAccuracy,
    String? photoPermisHeadingReference,
  }) {
    if (chauffeur.trim().isEmpty || numPermis.trim().isEmpty) {
      return left(const Failure.validation('Chauffeur et permis obligatoires'));
    }
    if (numPermis.trim().length > 12) {
      return left(
        const Failure.validation('Le permis est limité à 12 caractères'),
      );
    }
    if (plaqueArrivee?.trim().isNotEmpty != true) {
      return left(const Failure.validation('Plaque du camion obligatoire'));
    }
    return right(
      ArriveeDepot(
        lotId: lotId,
        chauffeur: chauffeur,
        numPermis: numPermis,
        numLot: numLot,
        gpsLat: lat,
        gpsLon: lon,
        statutGps: 'pending_server',
        plaqueArrivee: plaqueArrivee,
        plaqueCoherente: _coherente(plaqueArrivee, plaqueAttendue),
        photosDecharge: photosDecharge,
        photoArriveePath: photoArriveePath,
        photoArriveeHeadingDegrees: photoArriveeHeadingDegrees,
        photoArriveeHeadingAccuracy: photoArriveeHeadingAccuracy,
        photoArriveeHeadingReference: photoArriveeHeadingReference,
        photoPermisPath: photoPermisPath,
        photoPermisHeadingDegrees: photoPermisHeadingDegrees,
        photoPermisHeadingAccuracy: photoPermisHeadingAccuracy,
        photoPermisHeadingReference: photoPermisHeadingReference,
      ),
    );
  }

  /// Vrai si plaque d'arrivée == plaque attendue (anti-fraude immatriculation).
  /// Une plaque attendue absente ne peut pas être vérifiée.
  bool _coherente(String? arrivee, String? attendue) {
    if (arrivee == null || attendue == null) return false;
    String norm(String s) =>
        s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final plaqueArrivee = norm(arrivee);
    final plaqueAttendue = norm(attendue);
    return plaqueArrivee.isNotEmpty &&
        plaqueAttendue.isNotEmpty &&
        plaqueArrivee == plaqueAttendue;
  }
}
