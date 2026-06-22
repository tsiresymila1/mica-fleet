import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/entities/mine_chargement.dart';
import 'package:mica_fleet/features/loading/domain/usecases/add_mine_to_chargement.dart';
import 'package:mica_fleet/features/loading/domain/usecases/validate_chargement.dart';

CapturedPhoto _p() => CapturedPhoto(
    path: 'x',
    sha256: 'h',
    lat: -18.9,
    lon: 47.5,
    precision: 5,
    takenAt: DateTime(2026));

void main() {
  final c0 = Chargement(
      id: 'MICA-2026-0001',
      fournisseurId: 'F001',
      dateCreation: DateTime(2026));

  test('refuse une 4e mine', () {
    final add = AddMineToChargement();
    var c = c0;
    for (final id in ['a', 'b', 'c']) {
      c = add(c, MineChargement(mineId: id, photo: _p())).getRight().toNullable()!;
    }
    final r = add(c, const MineChargement(mineId: 'd'));
    expect(r.isLeft(), isTrue);
  });

  test('validation échoue si photo manquante', () {
    final c = c0.copyWith(mines: const [MineChargement(mineId: 'a')]);
    expect(ValidateChargement()(c).isLeft(), isTrue);
  });

  test('validation réussit avec 1 mine + photo', () {
    final c = c0.copyWith(mines: [MineChargement(mineId: 'a', photo: _p())]);
    expect(ValidateChargement()(c).getRight().toNullable()!.statut, 'valide');
  });
}
