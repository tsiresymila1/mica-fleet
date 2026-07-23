import 'entities/scoring_inputs.dart';
import 'entities/score_result.dart';

class ScoringEngine {
  ScoreResult evaluate(ScoringInputs i) {
    if (!_eligible(i)) {
      return const ScoreResult(eligible: false, score: 0, statut: 'rejete');
    }
    final score = (i.gpsVerifiable ? _gps(i.distanceGpsMetres) : _gpsNeutre) +
        _delai(i.ratioDelai) +
        (i.transportCoherent ? 20 : 0) +
        _quantite(i.ecartQuantitePct) +
        _historique(i.tauxConformite90j);
    return ScoreResult(eligible: true, score: score, statut: 'evalue');
  }

  bool _eligible(ScoringInputs i) =>
      i.gpsMineDansRayon &&
      i.photoMineValide &&
      i.fournisseurActif &&
      i.mineAutorisee &&
      i.donneesCompletes &&
      i.nombreMines >= 1 &&
      i.nombreMines <= 3 &&
      i.depotReconnu &&
      i.gpsNonFalsifie;

  // GPS non vérifiable (coords serveur absentes) : demi-crédit, pas 0.
  static const _gpsNeutre = 10;

  int _gps(double m) => m <= 20
      ? 20
      : m <= 50
          ? 15
          : m <= 100
              ? 10
              : 0;

  int _delai(double r) => r <= 1.0
      ? 25
      : r <= 1.10
          ? 18
          : r <= 1.25
              ? 12
              : r <= 1.50
                  ? 6
                  : 0;

  int _quantite(double pct) => pct <= 2
      ? 20
      : pct <= 5
          ? 15
          : pct <= 10
              ? 10
              : 0;

  int _historique(double t) => t >= 0.95
      ? 15
      : t >= 0.90
          ? 12
          : t >= 0.80
              ? 7
              : 0;
}
