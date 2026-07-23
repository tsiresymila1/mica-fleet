import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/scoring/domain/entities/scoring_inputs.dart';
import 'package:mica_fleet/features/scoring/domain/scoring_engine.dart';

ScoringInputs _base({
  bool gpsMine = true,
  int mines = 1,
  bool mock = false,
  double dist = 10,
  double ratio = 1.0,
  bool transport = true,
  double ecart = 1,
  double hist = 1.0,
  bool gpsVerifiable = true,
}) =>
    ScoringInputs(
        gpsMineDansRayon: gpsMine,
        photoMineValide: true,
        fournisseurActif: true,
        mineAutorisee: true,
        donneesCompletes: true,
        nombreMines: mines,
        depotReconnu: true,
        gpsNonFalsifie: !mock,
        distanceGpsMetres: dist,
        gpsVerifiable: gpsVerifiable,
        ratioDelai: ratio,
        transportCoherent: transport,
        ecartQuantitePct: ecart,
        tauxConformite90j: hist);

void main() {
  final engine = ScoringEngine();

  test('score parfait = 100', () {
    final r = engine.evaluate(_base());
    expect(r.eligible, isTrue);
    expect(r.score, 100);
  });

  test('GPS mine hors rayon → rejeté, score 0', () {
    final r = engine.evaluate(_base(gpsMine: false));
    expect(r.eligible, isFalse);
    expect(r.score, 0);
    expect(r.statut, 'rejete');
  });

  test('mock location → rejeté', () {
    expect(engine.evaluate(_base(mock: true)).eligible, isFalse);
  });

  test('4 mines → rejeté', () {
    expect(engine.evaluate(_base(mines: 4)).eligible, isFalse);
  });

  test('GPS non vérifiable (coords serveur absentes) → 10 pts neutres', () {
    // Distance énorme (comme un dépôt à 0,0) mais non vérifiable : on ne
    // pénalise pas — demi-crédit au lieu de 0. 10 + 25 + 20 + 20 + 15 = 90.
    final r = engine.evaluate(_base(dist: 999999, gpsVerifiable: false));
    expect(r.eligible, isTrue);
    expect(r.score, 90);
  });

  test('barèmes partiels cumulés', () {
    final r = engine.evaluate(_base(
        dist: 40, ratio: 1.25, transport: false, ecart: 8, hist: 0.92));
    expect(r.score, 15 + 12 + 0 + 10 + 12);
  });
}
