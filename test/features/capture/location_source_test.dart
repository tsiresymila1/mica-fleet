import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mica_fleet/features/capture/domain/services/location_source.dart';

void main() {
  test(
    'photo véhicule : accepte le premier GPS sans attendre sa précision',
    () async {
      final source = RealLocationSource(
        requirePreciseFix: false,
        ensureReady: () async {},
        accuracyStatus: () async => LocationAccuracyStatus.reduced,
        positions: (_) => Stream.fromIterable([
          _position(lat: -18.9, lon: 47.5, accuracy: 500),
          _position(lat: -18.91, lon: 47.51, accuracy: 5),
        ]),
      );
      final fix = await source.fix();
      expect(fix.lat, -18.9);
      expect(fix.accuracy, 500);
    },
  );

  test('photo véhicule : accepte une précision zéro sans seuil', () async {
    final source = RealLocationSource(
      requirePreciseFix: false,
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.reduced,
      positions: (_) =>
          Stream.value(_position(lat: -18.9, lon: 47.5, accuracy: 0)),
    );
    expect((await source.fix()).accuracy, 0);
  });

  test('photo véhicule : réutilise le GPS récent même imprécis', () async {
    final positions = StreamController<Position>(sync: true);
    final now = DateTime.utc(2026, 9, 17);
    final source = RealLocationSource(
      requirePreciseFix: false,
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.reduced,
      now: () => now,
      positions: (_) => positions.stream,
    );
    addTearDown(() async {
      await source.stopPreparing();
      await positions.close();
    });
    await source.prepare();
    positions.add(
      _position(lat: -18.9, lon: 47.5, accuracy: 100, timestamp: now),
    );
    expect((await source.fix()).accuracy, 100);
  });

  test('photo véhicule : ne contourne pas le refus du GPS simulé', () async {
    final source = RealLocationSource(
      requirePreciseFix: false,
      ensureReady: () async {},
      positions: (_) => Stream.value(
        _position(lat: -18.9, lon: 47.5, accuracy: 100, mocked: true),
      ),
    );
    await expectLater(
      source.fix(),
      throwsA(
        predicate((error) => error.toString().contains('Position GPS simulée')),
      ),
    );
  });

  test(
    'photo véhicule : GPS absent ou coordonnées invalides restent refusés',
    () async {
      final source = RealLocationSource(
        requirePreciseFix: false,
        ensureReady: () async {},
        positions: (_) =>
            Stream.value(_position(lat: double.nan, lon: 47.5, accuracy: 100)),
      );
      await expectLater(
        source.fix(),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('Aucune position GPS disponible'),
          ),
        ),
      );
    },
  );

  test('sélectionne le point précis sans attendre les suivants', () async {
    LocationSettings? requestedSettings;
    final source = RealLocationSource(
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.precise,
      positions: (settings) {
        requestedSettings = settings;
        return Stream.fromIterable([
          _position(lat: -18.9, lon: 47.5, accuracy: 20),
          _position(lat: -18.91, lon: 47.51, accuracy: 5),
          _position(lat: -18.92, lon: 47.52, accuracy: 2),
        ]);
      },
    );

    final fix = await source.fix();

    expect(fix.lat, -18.91);
    expect(fix.lon, 47.51);
    expect(fix.accuracy, 5);
    expect(requestedSettings?.accuracy, LocationAccuracy.bestForNavigation);
  });

  test('refuse la permission Android limitée à la position approximative', () {
    final source = RealLocationSource(
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.reduced,
      positions: (_) => const Stream.empty(),
    );

    expect(
      source.fix,
      throwsA(
        predicate((error) => error.toString().contains('Position précise')),
      ),
    );
  });

  test('refuse une mesure qui reste moins précise que 25 mètres', () {
    final source = RealLocationSource(
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.precise,
      positions: (_) =>
          Stream.value(_position(lat: -18.9, lon: 47.5, accuracy: 40)),
    );

    expect(
      source.fix,
      throwsA(
        predicate(
          (error) => error.toString().contains('Précision GPS insuffisante'),
        ),
      ),
    );
  });

  test(
    'limite le délai total même si les positions arrivent en continu',
    () async {
      final source = RealLocationSource(
        sampleTimeout: const Duration(milliseconds: 40),
        ensureReady: () async {},
        accuracyStatus: () async => LocationAccuracyStatus.precise,
        positions: (_) => Stream.periodic(
          const Duration(milliseconds: 2),
          (_) => _position(lat: -18.9, lon: 47.5, accuracy: 12),
        ),
      );

      final fix = await source.fix().timeout(const Duration(seconds: 1));

      expect(fix.accuracy, 12);
    },
  );

  test(
    'utilise immédiatement la dernière position préparée et récente',
    () async {
      final positions = StreamController<Position>(sync: true);
      var streamCount = 0;
      var clock = DateTime.utc(2026, 9, 16);
      final source = RealLocationSource(
        ensureReady: () async {},
        accuracyStatus: () async => LocationAccuracyStatus.precise,
        now: () => clock,
        positions: (_) {
          streamCount++;
          return positions.stream;
        },
      );
      addTearDown(() async {
        await source.stopPreparing();
        await positions.close();
      });
      await source.prepare();
      await source.prepare();
      positions.add(
        _position(lat: -18.9, lon: 47.5, accuracy: 12, timestamp: clock),
      );

      final first = await source.fix();
      clock = clock.add(const Duration(seconds: 1));
      positions.add(
        _position(lat: -18.91, lon: 47.51, accuracy: 10, timestamp: clock),
      );
      final second = await source.fix();

      expect(first.accuracy, 12);
      expect(second.lat, -18.91);
      expect(streamCount, 1);
    },
  );

  test('ne réutilise pas une position préparée devenue ancienne', () async {
    final positions = StreamController<Position>(sync: true);
    var clock = DateTime.utc(2026, 9, 16);
    final source = RealLocationSource(
      sampleTimeout: const Duration(milliseconds: 40),
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.precise,
      now: () => clock,
      positions: (_) => positions.stream,
    );
    addTearDown(() async {
      await source.stopPreparing();
      await positions.close();
    });
    await source.prepare();
    positions.add(
      _position(lat: -18.9, lon: 47.5, accuracy: 5, timestamp: clock),
    );
    clock = clock.add(const Duration(seconds: 4));

    await expectLater(
      source.fix(),
      throwsA(
        predicate(
          (error) => error.toString().contains('Aucune position GPS fiable'),
        ),
      ),
    );
  });

  test('refuse une position préparée simulée', () async {
    final positions = StreamController<Position>(sync: true);
    final source = RealLocationSource(
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.precise,
      positions: (_) => positions.stream,
    );
    addTearDown(() async {
      await source.stopPreparing();
      await positions.close();
    });
    await source.prepare();
    positions.add(_position(lat: -18.9, lon: 47.5, accuracy: 5, mocked: true));

    await expectLater(
      source.fix(),
      throwsA(
        predicate((error) => error.toString().contains('Position GPS simulée')),
      ),
    );
  });

  test('annule la préparation lorsque la caméra est fermée', () async {
    var cancelled = false;
    final positions = StreamController<Position>(
      onCancel: () => cancelled = true,
    );
    final source = RealLocationSource(
      ensureReady: () async {},
      accuracyStatus: () async => LocationAccuracyStatus.precise,
      positions: (_) => positions.stream,
    );
    await source.prepare();

    await source.stopPreparing();

    expect(cancelled, isTrue);
    await positions.close();
  });

  test(
    'ne démarre pas le GPS si la caméra est fermée pendant la permission',
    () async {
      final ready = Completer<void>();
      var streamCount = 0;
      final source = RealLocationSource(
        ensureReady: () => ready.future,
        accuracyStatus: () async => LocationAccuracyStatus.precise,
        positions: (_) {
          streamCount++;
          return const Stream.empty();
        },
      );
      final preparation = source.prepare();
      await source.stopPreparing();
      ready.complete();
      await preparation;

      expect(streamCount, 0);
    },
  );
}

Position _position({
  required double lat,
  required double lon,
  required double accuracy,
  DateTime? timestamp,
  bool mocked = false,
}) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: timestamp ?? DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: mocked,
);
