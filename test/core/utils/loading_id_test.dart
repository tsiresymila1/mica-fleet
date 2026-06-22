import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/utils/loading_id.dart';

void main() {
  test('format MICA-YYYY-XXXX avec année et séquence paddée', () {
    expect(buildLoadingId(2026, 7), 'MICA-2026-0007');
    expect(buildLoadingId(2026, 1234), 'MICA-2026-1234');
  });

  test('séquence > 9999 non tronquée', () {
    expect(buildLoadingId(2026, 12345), 'MICA-2026-12345');
  });
}
