import 'package:freezed_annotation/freezed_annotation.dart';
part 'arrivee_depot.freezed.dart';

@freezed
abstract class ArriveeDepot with _$ArriveeDepot {
  const factory ArriveeDepot({
    required String chargementId,
    required String depotId,
    required String chauffeur,
    required String numPermis,
    required String numLot,
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
