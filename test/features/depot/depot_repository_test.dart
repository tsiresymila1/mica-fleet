import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/capture/data/traceability_photo_store.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
import 'package:mica_fleet/features/capture/domain/entities/traceability_photos.dart';
import 'package:mica_fleet/features/depot/data/repositories/depot_repository_impl.dart';
import 'package:mica_fleet/features/depot/domain/entities/arrivee_depot.dart';
import 'package:mica_fleet/features/journal/data/journal_service.dart';
import 'package:mica_fleet/features/sync/data/chargement_snapshot_builder.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late DepotRepositoryImpl repo;
  late DriftLocalSyncStore sync;

  setUp(() async {
    db = AppDatabase.memory();
    sync = DriftLocalSyncStore(db);
    repo = DepotRepositoryImpl(db, sync, JournalService(db));
    await db
        .into(db.depots)
        .insert(
          DepotsCompanion.insert(
            id: 'D1',
            nom: 'Dépôt 1',
            lat: -18.9,
            lon: 47.5,
          ),
        );
    await db
        .into(db.depots)
        .insert(
          DepotsCompanion.insert(
            id: 'D2',
            nom: 'Inactif',
            lat: -19.0,
            lon: 47.6,
            actif: const Value(false),
          ),
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
            photoHeadingDegrees: const Value(15),
            photoHeadingAccuracy: const Value(1.5),
            photoHeadingReference: const Value('magnetic'),
          ),
        );
  });
  tearDown(() => db.close());

  test('activeDepots ne renvoie que les dépôts actifs', () async {
    final d = await repo.activeDepots();
    expect(d.map((x) => x.id).toList(), ['D1']);
  });

  test('persistArrivee enregistre et journalise la sync', () async {
    await db
        .into(db.transbordements)
        .insert(
          TransbordementsCompanion.insert(
            lotId: 'MICA-2026-0001-L1',
            ordre: 1,
            photoDechargeHeadingDegrees: const Value(90),
            photoDechargeHeadingAccuracy: const Value(2),
            photoDechargeHeadingReference: const Value('magnetic'),
            photoRechargeHeadingDegrees: const Value(180),
            photoRechargeHeadingAccuracy: const Value(3),
            photoRechargeHeadingReference: const Value('magnetic'),
          ),
        );
    final r = await repo.persistArrivee(
      const ArriveeDepot(
        lotId: 'MICA-2026-0001-L1',
        depotId: 'D1',
        chauffeur: 'Jean',
        numPermis: 'P1',
        numLot: 'L1',
        gpsLat: -18.9,
        gpsLon: 47.5,
        statutGps: 'valide',
        photoArriveeHeadingDegrees: 270,
        photoArriveeHeadingAccuracy: 4,
        photoArriveeHeadingReference: 'magnetic',
        photoPermisHeadingDegrees: 315,
        photoPermisHeadingAccuracy: 5,
        photoPermisHeadingReference: 'magnetic',
      ),
    );
    expect(r.isRight(), isTrue);

    final rows = await db.select(db.arriveesDepot).get();
    expect(rows.single.chauffeur, 'Jean');
    expect(rows.single.photoArriveeHeadingDegrees, 270);
    expect(rows.single.photoPermisHeadingDegrees, 315);

    // Envoi unique : à l'arrivée, une seule op 'lot' (snapshot complet du lot).
    final pending = await sync.pending(agentLogin: 'F001');
    expect(pending.single.entityType, 'lot');
    expect(
      Uuid.isValidUUID(fromString: pending.single.payload['id'] as String),
      isTrue,
    );
    expect(
      Uuid.isValidUUID(
        fromString: pending.single.payload['session_id'] as String,
      ),
      isTrue,
    );
    expect(
      pending.single.payload['id'],
      isNot(pending.single.payload['session_id']),
    );
    expect(pending.single.payload['arrival'], isNot(null));
    final mine = pending.single.payload['mine'] as Map<String, dynamic>;
    expect((mine['photo'] as Map)['heading_deg'], 15);
    final transload =
        (pending.single.payload['transloads'] as List).single as Map;
    expect((transload['photo_unload'] as Map)['heading_deg'], 90);
    expect((transload['photo_reload'] as Map)['heading_deg'], 180);
    final arrival = pending.single.payload['arrival'] as Map<String, dynamic>;
    expect((arrival['photo_arrival'] as Map)['heading_deg'], 270);
    expect((arrival['photo_license'] as Map)['heading_deg'], 315);
  });

  test('les UUID payload sont stables et la session est partagée', () async {
    await db
        .into(db.lots)
        .insert(
          LotsCompanion.insert(
            id: 'MICA-2026-0001-L2',
            sessionId: 'MICA-2026-0001',
            mineId: 'M002',
          ),
        );
    final builder = LotSnapshotBuilder(db);

    final first = await builder.build('MICA-2026-0001-L1');
    final second = await builder.build('MICA-2026-0001-L2');
    final replay = await builder.build('MICA-2026-0001-L1');

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.payload['id'], replay!.payload['id']);
    expect(first.payload['id'], isNot(second!.payload['id']));
    expect(first.payload['session_id'], second.payload['session_id']);
    expect(Uuid.isValidUUID(fromString: first.payload['id'] as String), isTrue);
    expect(
      Uuid.isValidUUID(fromString: first.payload['session_id'] as String),
      isTrue,
    );
  });

  test('snapshot v2 déclare les trois photos mine et dépôt', () async {
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
    TraceabilityPhotos set(String prefix) => TraceabilityPhotos(
      plate: photo('${prefix}_plate', 10),
      mica: photo('${prefix}_mica', 20),
      truckWithMica: photo('${prefix}_truck', 30),
    );
    await (db.update(db.lots)
          ..where((table) => table.id.equals('MICA-2026-0001-L1')))
        .write(const LotsCompanion(photoSchemaVersion: Value(2)));
    await TraceabilityPhotoStore(db).replace(
      lotId: 'MICA-2026-0001-L1',
      stage: TraceabilityPhotoStage.mine,
      stageOrder: 0,
      photos: set('mine'),
    );

    final result = await repo.persistArrivee(
      ArriveeDepot(
        lotId: 'MICA-2026-0001-L1',
        depotId: 'D1',
        chauffeur: 'Jean',
        numPermis: 'P1',
        numLot: 'L1',
        gpsLat: -18.9,
        gpsLon: 47.5,
        statutGps: 'valide',
        photosDecharge: set('depot'),
      ),
    );

    expect(result.isRight(), isTrue);
    final payload = (await sync.pending(agentLogin: 'F001')).single.payload;
    expect(payload['photo_schema_version'], 2);
    final mine = payload['mine'] as Map<String, dynamic>;
    final minePhotos = mine['photos'] as Map<String, dynamic>;
    expect((minePhotos['plate'] as Map)['key'], 'mine_plate');
    expect((minePhotos['mica'] as Map)['hash'], 'hash-mine_mica');
    expect((minePhotos['truck_with_mica'] as Map)['heading_deg'], 30);
    final arrival = payload['arrival'] as Map<String, dynamic>;
    final depotPhotos = arrival['photos_unload'] as Map<String, dynamic>;
    expect((depotPhotos['plate'] as Map)['key'], 'depot_unload_plate');
    expect(await db.select(db.lotTraceabilityPhotos).get(), hasLength(6));
  });
}
