import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/transport/domain/entities/transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/add_transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/remove_transbordement.dart';
import 'package:mica_fleet/features/transport/domain/usecases/validate_transbordement.dart';

void main() {
  test('add ajoute des maillons avec ordre croissant 0..N', () {
    final add = AddTransbordement();
    var c = <Transbordement>[];
    c = add(c, const Transbordement(ordre: 0, plaqueApres: 'B'));
    c = add(c, const Transbordement(ordre: 0, plaqueAvant: 'B', plaqueApres: 'C'));
    expect(c.map((m) => m.ordre).toList(), [1, 2]);
  });

  test('remove renumérote la chaîne', () {
    final add = AddTransbordement();
    final rem = RemoveTransbordement();
    var c = <Transbordement>[];
    for (var i = 0; i < 3; i++) {
      c = add(c, const Transbordement(ordre: 0));
    }
    c = rem(c, 2);
    expect(c.map((m) => m.ordre).toList(), [1, 2]);
  });

  test('validate marque conforme si dans le rayon', () {
    final v = ValidateTransbordement();
    final c = [
      const Transbordement(
          ordre: 1,
          gpsDechargeLat: -18.90000,
          gpsDechargeLon: 47.5,
          gpsRechargeLat: -18.90010,
          gpsRechargeLon: 47.5),
    ];
    expect(v(c, 20).single.conforme, isTrue);
  });

  test('chaineCoherente vraie si plaques s enchaînent', () {
    final v = ValidateTransbordement();
    final c = [
      const Transbordement(ordre: 1, plaqueApres: 'B'),
      const Transbordement(ordre: 2, plaqueAvant: 'B', plaqueApres: 'C'),
    ];
    expect(v.chaineCoherente(c), isTrue);
  });
}
