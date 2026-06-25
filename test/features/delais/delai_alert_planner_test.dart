import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/delais/domain/delai_alert_planner.dart';

void main() {
  final planner = DelaiAlertPlanner();
  final debut = DateTime(2026, 6, 1, 8, 0);

  test('deux rappels : avant échéance (80%) et échéance', () {
    final r = planner.planifier(debut, const Duration(hours: 10));
    expect(r.length, 2);
    expect(r[0].type, DelaiAlerte.avantEcheance);
    expect(r[0].quand, debut.add(const Duration(hours: 8))); // 80% de 10h
    expect(r[1].type, DelaiAlerte.echeance);
    expect(r[1].quand, debut.add(const Duration(hours: 10)));
  });

  test('seuil personnalisable', () {
    final r = planner.planifier(debut, const Duration(hours: 10), seuil: 0.5);
    expect(r[0].quand, debut.add(const Duration(hours: 5)));
  });
}
