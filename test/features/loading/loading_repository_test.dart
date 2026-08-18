import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/capture/domain/entities/traceability_photos.dart';
import 'package:mica_fleet/features/journal/data/journal_service.dart';
import 'package:mica_fleet/features/loading/data/repositories/loading_repository_impl.dart';
import 'package:mica_fleet/features/loading/domain/entities/chargement.dart';
import 'package:mica_fleet/features/loading/domain/entities/lot.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';

void main() {
  late AppDatabase db;
  late LoadingRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.memory();
    repo = LoadingRepositoryImpl(
      db,
      DriftLocalSyncStore(db),
      JournalService(db),
    );
    await db
        .into(db.chargements)
        .insert(
          ChargementsCompanion.insert(
            id: 'MICA-2026-0001',
            fournisseurId: 'F001',
            dateCreation: DateTime(2026),
          ),
        );
    await db
        .into(db.lots)
        .insert(
          LotsCompanion.insert(
            id: 'MICA-2026-0001-L1',
            sessionId: 'MICA-2026-0001',
            mineId: 'M001',
          ),
        );
  });
  tearDown(() => db.close());

  test('supprime une session non arrivée + ses lots', () async {
    final r = await repo.deleteChargement('MICA-2026-0001');
    expect(r.isRight(), isTrue);
    expect(await db.select(db.chargements).get(), isEmpty);
    expect(await db.select(db.lots).get(), isEmpty);
  });

  test('persiste le heading de la photo de départ du lot', () async {
    final result = await repo.persist(
      Chargement(
        id: 'MICA-2026-0001',
        fournisseurId: 'F001',
        dateCreation: DateTime(2026),
        lots: [
          Lot(
            id: 'MICA-2026-0001-L1',
            mineId: 'M001',
            photo: CapturedPhoto(
              path: '/tmp/mine.jpg',
              sha256: 'hash',
              lat: -18.9,
              lon: 47.5,
              precision: 3,
              takenAt: DateTime(2026),
              headingDegrees: 15,
              headingAccuracy: 1.5,
              headingReference: 'magnetic',
            ),
          ),
        ],
      ),
    );

    expect(result.isRight(), isTrue);
    final lot = (await db.select(db.lots).get()).single;
    expect(lot.photoHeadingDegrees, 15);
    expect(lot.photoHeadingAccuracy, 1.5);
    expect(lot.photoHeadingReference, 'magnetic');
  });

  test('persiste les deux preuves v3 du chargement mine', () async {
    CapturedPhoto photo(String name, double heading) => CapturedPhoto(
      path: '/tmp/$name.jpg',
      sha256: 'hash-$name',
      lat: -18.9,
      lon: 47.5,
      precision: 3,
      takenAt: DateTime.utc(2026, 8, 13),
      headingDegrees: heading,
      headingReference: 'magnetic',
    );
    final result = await repo.persist(
      Chargement(
        id: 'MICA-2026-0001',
        fournisseurId: 'F001',
        dateCreation: DateTime(2026),
        lots: [
          Lot(
            id: 'MICA-2026-0001-L1',
            mineId: 'M001',
            photos: TraceabilityPhotos(
              plate: photo('plate', 10),
              truckWithMica: photo('truck', 30),
            ),
          ),
        ],
      ),
    );

    expect(result.isRight(), isTrue);
    final lot = (await db.select(db.lots).get()).single;
    expect(lot.photoSchemaVersion, 3);
    final photos = await db.select(db.lotTraceabilityPhotos).get();
    expect(photos, hasLength(2));
    expect(photos.map((row) => row.role).toSet(), {'plate', 'truck_with_mica'});
    expect(photos.singleWhere((row) => row.role == 'plate').headingDegrees, 10);
  });

  test('refuse la suppression si un lot est arrivé au dépôt', () async {
    await db
        .into(db.depots)
        .insert(
          DepotsCompanion.insert(id: 'D1', nom: 'D', lat: -18.9, lon: 47.5),
        );
    await db
        .into(db.arriveesDepot)
        .insert(
          ArriveesDepotCompanion.insert(
            lotId: 'MICA-2026-0001-L1',
            depotId: const Value('D1'),
            chauffeur: 'J',
            numPermis: 'P',
            numLot: 'L',
            gpsLat: -18.9,
            gpsLon: 47.5,
            statutGps: 'valide',
          ),
        );
    final r = await repo.deleteChargement('MICA-2026-0001');
    expect(r.isLeft(), isTrue);
    expect(await db.select(db.chargements).get(), isNotEmpty);
  });

  test('supprime un lot local et son cache associé', () async {
    await db
        .into(db.lotTraceabilityPhotos)
        .insert(
          LotTraceabilityPhotosCompanion.insert(
            lotId: 'MICA-2026-0001-L1',
            stage: 'mine',
            stageOrder: const Value(0),
            role: 'plate',
            path: '/tmp/p1.jpg',
            hash: 'hash',
            lat: -18.9,
            lon: 47.5,
            gpsAccuracy: 3,
            capturedAt: DateTime(2026),
          ),
        );
    await db
        .into(db.transbordements)
        .insert(
          TransbordementsCompanion.insert(
            lotId: 'MICA-2026-0001-L1',
            ordre: 1,
            plaqueAvant: const Value('ABC'),
          ),
        );
    await db
        .into(db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            opId: 'op-delete-lot',
            entityType: 'lot',
            entityId: 'MICA-2026-0001-L1',
            opType: 'delete',
            payload: '{}',
            createdAt: DateTime(2026),
          ),
        );

    final r = await repo.deleteLot('MICA-2026-0001-L1');
    expect(r.isRight(), isTrue);
    expect(await db.select(db.lots).get(), isEmpty);
    expect(await db.select(db.lotTraceabilityPhotos).get(), isEmpty);
    expect(await db.select(db.transbordements).get(), isEmpty);
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('refuse la suppression locale d’un lot déjà arrivé', () async {
    await db
        .into(db.chargements)
        .insert(
          ChargementsCompanion.insert(
            id: 'MICA-2026-0002',
            fournisseurId: 'F001',
            dateCreation: DateTime(2026),
          ),
        );
    await db
        .into(db.lots)
        .insert(
          LotsCompanion.insert(
            id: 'MICA-2026-0002-L1',
            sessionId: 'MICA-2026-0002',
            mineId: 'M002',
          ),
        );
    await db
        .into(db.arriveesDepot)
        .insert(
          ArriveesDepotCompanion.insert(
            lotId: 'MICA-2026-0002-L1',
            chauffeur: 'J',
            numPermis: 'P',
            numLot: 'L',
            gpsLat: -18.9,
            gpsLon: 47.5,
            statutGps: 'valide',
          ),
        );

    final r = await repo.deleteLot('MICA-2026-0002-L1');
    expect(r.isLeft(), isTrue);
    expect(
      (await db.select(db.lots).get()).map((e) => e.id),
      contains('MICA-2026-0002-L1'),
    );
  });
}
