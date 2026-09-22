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

  test('ignore un faux nord dont la précision est inconnue', () async {
    final source = CompassHeadingSource(
      useCameraHeading: false,
      events: () => Stream.fromIterable([
        CompassEvent.fromList([0, 0, -1]),
        CompassEvent.fromList([90, 0, 15]),
      ]),
    );

    final heading = await source.current();

    expect(heading?.degrees, 90);
    expect(heading?.accuracy, 15);
  });

  test('moyenne correctement les caps autour de zéro degré', () async {
    final source = CompassHeadingSource(
      sampleCount: 2,
      useCameraHeading: false,
      events: () => Stream.fromIterable([
        CompassEvent.fromList([359, 0, 3]),
        CompassEvent.fromList([1, 0, 3]),
      ]),
    );

    final heading = await source.current();

    expect(heading, isNotNull);
    expect(heading!.degrees, closeTo(0, 0.001));
  });

  test('retourne null si aucune mesure fiable n’est disponible', () async {
    final source = CompassHeadingSource(
      useCameraHeading: false,
      events: () => Stream.value(CompassEvent.fromList([0, 0, -1])),
    );

    expect(await source.current(), isNull);
  });
}
