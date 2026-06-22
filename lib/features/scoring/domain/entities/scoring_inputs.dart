import 'package:freezed_annotation/freezed_annotation.dart';
part 'scoring_inputs.freezed.dart';

@freezed
abstract class ScoringInputs with _$ScoringInputs {
  const factory ScoringInputs({
    // Niveau 1 — éligibilité
    required bool gpsMineDansRayon,
    required bool photoMineValide,
    required bool fournisseurActif,
    required bool mineAutorisee,
    required bool donneesCompletes,
    required int nombreMines,
    required bool depotReconnu,
    required bool gpsNonFalsifie,
    // Niveau 2 — conformité
    required double distanceGpsMetres, // A
    required double ratioDelai, // B : temps écoulé / limite (1.0 = pile)
    required bool transportCoherent, // C
    required double ecartQuantitePct, // D : écart en %
    required double tauxConformite90j, // E : 0..1
  }) = _ScoringInputs;
}
