import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
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
          ),
        );
  });
  tearDown(() => db.close());

  test('activeDepots ne renvoie que les dépôts actifs', () async {
    final d = await repo.activeDepots();
    expect(d.map((x) => x.id).toList(), ['D1']);
  });

  test('persistArrivee enregistre et journalise la sync', () async {
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
      ),
    );
    expect(r.isRight(), isTrue);

    final rows = await db.select(db.arriveesDepot).get();
    expect(rows.single.chauffeur, 'Jean');

    // Envoi unique : à l'arrivée, une seule op 'lot' (snapshot complet du lot).
    final pending = await sync.pending();
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
}
