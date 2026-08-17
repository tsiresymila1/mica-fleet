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
      const Depot(id: 'DY', nom: 'Y', lat: -18.9, lon: 47.5, rayonMetres: 0),
    ];
    final n = DetectDepot().nearest(casse, -18.9, 47.5);
    expect(n?.statutGps, 'non_verifiable');
  });

  test('nearest : aucun dépôt → null', () {
    expect(DetectDepot().nearest(const [], -18.9, 47.5), isNull);
  });

  test('validate délègue le dépôt et le statut GPS au serveur', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.95,
      lon: 47.55,
      chauffeur: 'Jean',
      numPermis: 'P1',
      numLot: 'L1',
    );
    final arrivee = r.getRight().toNullable()!;
    expect(arrivee.statutGps, 'pending_server');
    expect(arrivee.depotId, isNull);
  });

  test('validate échoue si champs obligatoires vides', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.9,
      lon: 47.5,
      chauffeur: '',
      numPermis: 'P1',
      numLot: 'L1',
    );
    expect(r.isLeft(), isTrue);
  });

  test('validate réussit sans numéro de lot fourni par le mobile', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.90005,
      lon: 47.5,
      chauffeur: 'Jean',
      numPermis: 'P1',
      numLot: '',
    );
    expect(r.isRight(), isTrue);
  });

  test('plaque cohérente si arrivée == attendue (normalisée)', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.90005,
      lon: 47.5,
      chauffeur: 'J',
      numPermis: 'P',
      numLot: 'L',
      plaqueArrivee: '1234 tbr',
      plaqueAttendue: '1234-TBR',
    );
    expect(r.getRight().toNullable()!.plaqueCoherente, isTrue);
  });

  test('plaque incohérente si arrivée != attendue', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.90005,
      lon: 47.5,
      chauffeur: 'J',
      numPermis: 'P',
      numLot: 'L',
      plaqueArrivee: '9999 ABC',
      plaqueAttendue: '1234 TBR',
    );
    expect(r.getRight().toNullable()!.plaqueCoherente, isFalse);
  });

  test('plaque non vérifiable si la plaque attendue est inconnue', () {
    final r = ValidateArrivee()(
      lotId: 'MICA-2026-0001-L1',
      lat: -18.90005,
      lon: 47.5,
      chauffeur: 'J',
      numPermis: 'P',
      numLot: 'L',
      plaqueArrivee: '9999 ABC',
      plaqueAttendue: null,
    );
    expect(r.getRight().toNullable()!.plaqueCoherente, isFalse);
  });
}
