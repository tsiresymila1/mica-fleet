import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/entities/lot.dart';
import 'package:mica_fleet/features/loading/domain/usecases/add_lot_to_chargement.dart';
import 'package:mica_fleet/features/loading/domain/usecases/validate_chargement.dart';

CapturedPhoto _p() => CapturedPhoto(
    path: 'x',
    sha256: 'h',
    lat: -18.9,
    lon: 47.5,
    precision: 5,
    takenAt: DateTime(2026));

Lot _lot(String mineId, {CapturedPhoto? photo}) =>
    Lot(id: '', mineId: mineId, photo: photo);

void main() {
  final c0 = Chargement(
      id: 'MICA-2026-0001',
      fournisseurId: 'F001',
      dateCreation: DateTime(2026));

  test('refuse un 4e lot (max 3 mines)', () {
    final add = AddLotToChargement();
    var c = c0;
    for (final id in ['a', 'b', 'c']) {
      c = add(c, _lot(id, photo: _p())).getRight().toNullable()!;
    }
    expect(add(c, _lot('d')).isLeft(), isTrue);
  });

  test('refuse deux lots issus de la même mine', () {
    final add = AddLotToChargement();
    final c = add(c0, _lot('a', photo: _p())).getRight().toNullable()!;
    expect(add(c, _lot('a', photo: _p())).isLeft(), isTrue);
  });

  test('chaque lot reçoit un id <session>-L<n>', () {
    final add = AddLotToChargement();
    var c = add(c0, _lot('a', photo: _p())).getRight().toNullable()!;
    c = add(c, _lot('b', photo: _p())).getRight().toNullable()!;
    expect(c.lots.map((l) => l.id), ['MICA-2026-0001-L1', 'MICA-2026-0001-L2']);
  });

  test('validation échoue si photo manquante', () {
    final c = c0.copyWith(lots: [_lot('a')]);
    expect(ValidateChargement()(c).isLeft(), isTrue);
  });

  test('validation réussit avec 1 lot + photo', () {
    final c = c0.copyWith(lots: [_lot('a', photo: _p())]);
    expect(ValidateChargement()(c).getRight().toNullable()!.statut, 'valide');
  });
}
