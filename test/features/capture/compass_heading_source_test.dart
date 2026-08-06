import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/features/capture/data/compass_heading_source.dart';

void main() {
  test('utilise le cap caméra et le normalise entre 0 et 360 degrés', () async {
    final source = CompassHeadingSource(
      events: () => Stream.value(CompassEvent.fromList([15, -20, 3])),
    );

    final heading = await source.current();

    expect(heading?.degrees, 340);
    expect(heading?.accuracy, 3);
    expect(heading?.reference, 'magnetic');
  });

  test('retourne null quand la boussole est indisponible', () async {
    final source = CompassHeadingSource(events: () => null);

    expect(await source.current(), isNull);
  });

  test(
    'sur Android utilise heading car headingForCameraMode reste à zéro',
    () async {
      final source = CompassHeadingSource(
        useCameraHeading: false,
        events: () => Stream.value(CompassEvent.fromList([125, 0, 3])),
      );

      final heading = await source.current();

      expect(heading?.degrees, 125);
    },
  );
}
