import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/depot/domain/entities/depot.dart';
import 'package:mica_fleet/features/depot/domain/usecases/detect_depot.dart';
import 'package:mica_fleet/features/depot/domain/usecases/validate_arrivee.dart';

void main() {
  final depots = [
    const Depot(id: 'D1', nom: 'Dépôt 1', lat: -18.9, lon: 47.5),
    const Depot(id: 'D2', nom: 'Dépôt 2', lat: -19.0, lon: 47.6),
  ];

  test('detect renvoie le dépôt dont la zone contient le point', () {
    final d = DetectDepot()(depots, -18.90005, 47.5);
    expect(d?.id, 'D1');
  });

  test('detect renvoie null hors zone', () {
    expect(DetectDepot()(depots, -18.95, 47.55), isNull);
  });

  test('nearest : dans la zone → valide', () {
    final n = DetectDepot().nearest(depots, -18.90005, 47.5);
    expect(n?.depot.id, 'D1');
    expect(n?.statutGps, 'valide');
  });

  test('nearest : hors zone → hors_zone (ne bloque pas)', () {
    final n = DetectDepot().nearest(depots, -18.95, 47.55);
    expect(n, isNotNull);
    expect(n!.statutGps, 'hors_zone');
    expect(n.distanceMetres, greaterThan(20));
  });

  test('nearest : coords serveur nulles → non_verifiable', () {
    final casse = [const Depot(id: 'DX', nom: 'X', lat: 0, lon: 0)];
    final n = DetectDepot().nearest(casse, -18.9, 47.5);
    expect(n?.statutGps, 'non_verifiable');
  });

  test('nearest : rayon 0 → non_verifiable', () {
    final casse = [
      const Depot(id: 'DY', nom: 'Y', lat: -18.9, lon: 47.5, rayonMetres: 0)
    ];
    final n = DetectDepot().nearest(casse, -18.9, 47.5);
    expect(n?.statutGps, 'non_verifiable');
  });

  test('nearest : aucun dépôt → null', () {
    expect(DetectDepot().nearest(const [], -18.9, 47.5), isNull);
  });

  test('validate hors zone → réussit en hors_zone (plus de blocage)', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1',
        depots: depots,
        lat: -18.95,
        lon: 47.55,
        chauffeur: 'Jean',
        numPermis: 'P1',
        numLot: 'L1');
    expect(r.getRight().toNullable()!.statutGps, 'hors_zone');
  });

  test('validate échoue si champs obligatoires vides', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1',
        depots: depots,
        lat: -18.9,
        lon: 47.5,
        chauffeur: '',
        numPermis: 'P1',
        numLot: 'L1');
    expect(r.isLeft(), isTrue);
  });

  test('validate réussit dans la zone avec champs remplis', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1',
        depots: depots,
        lat: -18.90005,
        lon: 47.5,
        chauffeur: 'Jean',
        numPermis: 'P1',
        numLot: 'L1');
    expect(r.getRight().toNullable()!.depotId, 'D1');
  });

  test('plaque cohérente si arrivée == attendue (normalisée)', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '1234 tbr', plaqueAttendue: '1234-TBR');
    expect(r.getRight().toNullable()!.plaqueCoherente, isTrue);
  });

  test('plaque incohérente si arrivée != attendue', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '9999 ABC', plaqueAttendue: '1234 TBR');
    expect(r.getRight().toNullable()!.plaqueCoherente, isFalse);
  });

  test('plaque cohérente par défaut si attendue inconnue', () {
    final r = ValidateArrivee(DetectDepot())(
        lotId: 'MICA-2026-0001-L1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '9999 ABC', plaqueAttendue: null);
    expect(r.getRight().toNullable()!.plaqueCoherente, isTrue);
  });
}
