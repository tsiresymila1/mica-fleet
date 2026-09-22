import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/trip/data/trip_tracker.dart';
import 'package:mica_fleet/features/trip/data/background_trip_service.dart';

class _BackgroundTripService implements BackgroundTripService {
  String? session;
  int stops = 0;
  @override
  Future<bool> isRunning() async => session != null;
  @override
  Future<void> start(String chargementId) async => session = chargementId;
  @override
  Future<void> stop() async {
    stops++;
    session = null;
  }
}

void main() {
  late AppDatabase db;
  late TripTracker tracker;

  setUp(() async {
    db = AppDatabase.memory();
    tracker = TripTracker(db);
    await db
        .into(db.chargements)
        .insert(
          ChargementsCompanion.insert(
            id: 'C1',
            fournisseurId: 'F001',
            dateCreation: DateTime(2026),
          ),
        );
  });
  tearDown(() async {
    await tracker.stop();
    await db.close();
  });

  test('ignore un point trop proche (<8m), garde les éloignés', () async {
    await tracker.recordPoint('C1', -18.90000, 47.5, simule: true);
    // ~5 m plus loin → ignoré
    await tracker.recordPoint('C1', -18.90004, 47.5, simule: true);
    // ~50 m plus loin → gardé
    await tracker.recordPoint('C1', -18.90050, 47.5, simule: true);
    final pts = await db.select(db.trajetPoints).get();
    expect(pts.length, 2);
  });

  test('ignore les positions GPS trop imprécises', () async {
    await tracker.recordPoint('C1', -18.9, 47.5, accuracy: 40);
    await tracker.recordPoint('C1', -18.9005, 47.5, accuracy: 5);

    final pts = await db.select(db.trajetPoints).get();

    expect(pts, hasLength(1));
    expect(pts.single.lat, -18.9005);
  });

  test('confirme le déplacement incertain avant de sauvegarder', () async {
    final start = DateTime(2026);
    await tracker.recordPoint('C1', -18.9, 47.5, accuracy: 20, at: start);
    await tracker.recordPoint(
      'C1',
      -18.900074,
      47.5,
      accuracy: 20,
      at: start.add(const Duration(seconds: 3)),
    );
    expect(await db.select(db.trajetPoints).get(), hasLength(1));
    await tracker.recordPoint(
      'C1',
      -18.900094,
      47.5,
      accuracy: 20,
      at: start.add(const Duration(seconds: 6)),
    );
    await tracker.recordPoint(
      'C1',
      -18.900114,
      47.5,
      accuracy: 20,
      at: start.add(const Duration(seconds: 9)),
    );
    final points = await db.select(db.trajetPoints).get();
    expect(points, hasLength(2));
    expect(points.last.lat, -18.900114);
  });

  test('refuse les coordonnées invalides', () async {
    await tracker.recordPoint('C1', double.nan, 47.5, accuracy: 5);
    await tracker.recordPoint('C1', 95, 47.5, accuracy: 5);
    expect(await db.select(db.trajetPoints).get(), isEmpty);
  });

  test('délègue le suivi réel au service Android persistant', () async {
    final service = _BackgroundTripService();
    tracker = TripTracker(
      db,
      ensureReady: () async {},
      backgroundService: service,
    );
    await tracker.start('C1');
    expect(service.session, 'C1');
    expect(tracker.isTracking, isTrue);
    await tracker.stop();
    expect(service.session, isNull);
    expect(service.stops, 1);
  });

  test(
    'restaure une session avec lot en route et arrête une session terminée',
    () async {
      final service = _BackgroundTripService();
      tracker = TripTracker(
        db,
        ensureReady: () async {},
        backgroundService: service,
      );
      await db
          .into(db.mines)
          .insert(MinesCompanion.insert(id: 'M1', nom: 'Mine', lat: 0, lon: 0));
      await db
          .into(db.lots)
          .insert(
            LotsCompanion.insert(id: 'L1', sessionId: 'C1', mineId: 'M1'),
          );
      await tracker.restoreFromDatabase();
      expect(service.session, 'C1');

      await db
          .into(db.arriveesDepot)
          .insert(
            ArriveesDepotCompanion.insert(
              lotId: 'L1',
              gpsLat: 0,
              gpsLon: 0,
              chauffeur: 'A',
              numPermis: 'P',
              numLot: '',
              statutGps: 'valide',
            ),
          );
      await tracker.restoreFromDatabase();
      expect(service.session, isNull);
    },
  );

  test(
    'une écriture échouée ne déplace pas le dernier point enregistré',
    () async {
      final start = DateTime(2026);
      await tracker.recordPoint('C1', -18.9, 47.5, accuracy: 5, at: start);
      await tracker.recordPoint(
        'C1',
        -18.90009,
        47.5,
        accuracy: 5,
        at: start.add(const Duration(seconds: 3)),
      );
      await db.customStatement('''
      CREATE TRIGGER fail_gps BEFORE INSERT ON trajet_points
      BEGIN SELECT RAISE(ABORT, 'test write failure'); END
    ''');
      await expectLater(
        tracker.recordPoint(
          'C1',
          -18.90012,
          47.5,
          accuracy: 5,
          at: start.add(const Duration(seconds: 6)),
        ),
        throwsA(anything),
      );
      await db.customStatement('DROP TRIGGER fail_gps');
      await tracker.recordPoint(
        'C1',
        -18.90013,
        47.5,
        accuracy: 5,
        at: start.add(const Duration(seconds: 9)),
      );
      final points = await db.select(db.trajetPoints).get();
      expect(points, hasLength(2));
      expect(points.last.lat, -18.90013);
    },
  );

  test(
    'le flux GPS enregistre en base locale sans aucune dépendance réseau',
    () async {
      final positions = StreamController<Position>();
      tracker = TripTracker(
        db,
        ensureReady: () async {},
        positions: (settings) {
          expect(settings.accuracy, LocationAccuracy.bestForNavigation);
          expect(settings.distanceFilter, 0);
          return positions.stream;
        },
      );
      await tracker.start('C1');
      positions.add(_position(-18.9, 0));
      positions.add(_position(-18.900074, 3));
      positions.add(_position(-18.900094, 6));
      final points = await db
          .select(db.trajetPoints)
          .watch()
          .firstWhere((rows) => rows.length == 2)
          .timeout(const Duration(seconds: 2));
      expect(points, hasLength(2));
      await tracker.stop();
      await positions.close();
    },
  );
}

Position _position(double lat, int seconds) => Position(
  latitude: lat,
  longitude: 47.5,
  timestamp: DateTime(2026).add(Duration(seconds: seconds)),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);
