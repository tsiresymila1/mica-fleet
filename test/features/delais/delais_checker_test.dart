import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/delais/domain/delais_checker.dart';

void main() {
  final c = DelaisChecker();
  const limite = Duration(hours: 24);

  test('ok bien avant échéance', () {
    expect(c.statut(const Duration(hours: 10), limite), DelaiStatut.ok);
  });
  test('bientôt échu à 80%+', () {
    expect(c.statut(const Duration(hours: 20), limite), DelaiStatut.bientotEchu);
  });
  test('dépassé au-delà de la limite', () {
    expect(c.statut(const Duration(hours: 25), limite), DelaiStatut.depasse);
  });
  test('ratio = écoulé/limite', () {
    expect(c.ratio(const Duration(hours: 12), limite), closeTo(0.5, 0.001));
  });
}
