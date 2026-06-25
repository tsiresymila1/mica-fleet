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

  test('validate échoue si champs obligatoires vides', () {
    final r = ValidateArrivee(DetectDepot())(
        chargementId: 'MICA-2026-0001',
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
        chargementId: 'MICA-2026-0001',
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
        chargementId: 'C1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '1234 tbr', plaqueAttendue: '1234-TBR');
    expect(r.getRight().toNullable()!.plaqueCoherente, isTrue);
  });

  test('plaque incohérente si arrivée != attendue', () {
    final r = ValidateArrivee(DetectDepot())(
        chargementId: 'C1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '9999 ABC', plaqueAttendue: '1234 TBR');
    expect(r.getRight().toNullable()!.plaqueCoherente, isFalse);
  });

  test('plaque cohérente par défaut si attendue inconnue', () {
    final r = ValidateArrivee(DetectDepot())(
        chargementId: 'C1', depots: depots, lat: -18.90005, lon: 47.5,
        chauffeur: 'J', numPermis: 'P', numLot: 'L',
        plaqueArrivee: '9999 ABC', plaqueAttendue: null);
    expect(r.getRight().toNullable()!.plaqueCoherente, isTrue);
  });
}
