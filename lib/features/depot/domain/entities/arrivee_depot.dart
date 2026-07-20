import 'package:freezed_annotation/freezed_annotation.dart';
part 'arrivee_depot.freezed.dart';

/// Arrivée d'UN lot au dépôt (un lot arrive en un seul camion).
@freezed
abstract class ArriveeDepot with _$ArriveeDepot {
  const factory ArriveeDepot({
    required String lotId,
    required String depotId,
    required String chauffeur,
    required String numPermis,
    required String numLot, // numéro de lot (1 lot = 1 traçabilité)
    required double gpsLat,
    required double gpsLon,
    required String statutGps, // valide / hors_zone
    String? plaqueArrivee,
    @Default(true) bool plaqueCoherente,
    int? scoreTracabilite,
    String? photoPermisPath,
    String? photoArriveePath,
  }) = _ArriveeDepot;
}
