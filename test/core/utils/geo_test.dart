import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/utils/geo.dart';

void main() {
  test('distance 0 entre point identique', () {
    expect(haversineMeters(-18.9, 47.5, -18.9, 47.5), closeTo(0, 0.001));
  });

  test('distance ~111320 m pour 1 degré de latitude', () {
    expect(haversineMeters(0, 0, 1, 0), closeTo(111320, 200));
  });

  test('isWithinRadius vrai si distance <= rayon', () {
    expect(isWithinRadius(-18.90000, 47.50000, -18.90013, 47.50000, 20), isTrue);
    expect(isWithinRadius(-18.90000, 47.50000, -18.90050, 47.50000, 20), isFalse);
  });
}
