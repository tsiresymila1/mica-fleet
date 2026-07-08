import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/trip/domain/trip_simulator.dart';

void main() {
  final sim = TripSimulator();
  const depart = SimPoint(-18.91, 47.52);
  const depot = SimPoint(-18.879, 47.508);

  test('génère steps+1 points, extrémités exactes', () {
    final (pts, idx) = sim.generate(depart, depot, steps: 20);
    expect(pts.length, 21);
    expect(pts.first.lat, depart.lat);
    expect(pts.first.lon, depart.lon);
    expect(pts.last.lat, depot.lat);
    expect(pts.last.lon, depot.lon);
    expect(idx, 8); // 40% de 20
  });

  test('déterministe pour un même seed', () {
    final a = sim.generate(depart, depot, seed: 3).$1;
    final b = sim.generate(depart, depot, seed: 3).$1;
    expect(a[5].lat, b[5].lat);
    expect(a[5].lon, b[5].lon);
  });

  test('transbordement entre départ et dépôt', () {
    final (pts, idx) = sim.generate(depart, depot);
    // latitude du transbordement entre les deux extrémités
    final loLat = depart.lat < depot.lat ? depart.lat : depot.lat;
    final hiLat = depart.lat < depot.lat ? depot.lat : depart.lat;
    expect(pts[idx].lat, greaterThanOrEqualTo(loLat - 0.001));
    expect(pts[idx].lat, lessThanOrEqualTo(hiLat + 0.001));
  });
}
