import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/update/data/drift_update_readiness_repository.dart';

void main() {
  late AppDatabase db;
  late DriftUpdateReadinessRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = DriftUpdateReadinessRepository(db);
  });

  tearDown(() => db.close());

  test('bloque pour file, lot ou proposition encore locale', () async {
    await db
        .into(db.mines)
        .insert(
          MinesCompanion.insert(id: 'mine-1', nom: 'Mine', lat: 0, lon: 0),
        );
    await db
        .into(db.chargements)
        .insert(
          ChargementsCompanion.insert(
            id: 'session-1',
            fournisseurId: 'agent',
            dateCreation: DateTime.utc(2026, 8, 31),
          ),
        );
    await db
        .into(db.lots)
        .insert(
          LotsCompanion.insert(
            id: 'lot-1',
            sessionId: 'session-1',
            mineId: 'mine-1',
          ),
        );
    await db
        .into(db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            opId: 'op-1',
            entityType: 'password',
            entityId: 'agent',
            opType: 'update',
            payload: '{}',
            createdAt: DateTime.utc(2026, 8, 31),
            status: const Value('failed'),
          ),
        );
    await db
        .into(db.mineSubmissions)
        .insert(
          MineSubmissionsCompanion.insert(
            payloadId: 'mine-payload-1',
            deviceUuid: 'device-1',
            nom: 'Mine locale',
            createdAt: DateTime.utc(2026, 8, 31),
            updatedAt: DateTime.utc(2026, 8, 31),
          ),
        );

    expect(await repository.unsyncedDataCount(), 3);

    await (db.update(db.syncQueue)..where((t) => t.opId.equals('op-1'))).write(
      const SyncQueueCompanion(status: Value('synced')),
    );
    await (db.update(db.lots)..where((t) => t.id.equals('lot-1'))).write(
      const LotsCompanion(photosUploaded: Value(true)),
    );
    await (db.update(
      db.mineSubmissions,
    )..where((t) => t.payloadId.equals('mine-payload-1'))).write(
      const MineSubmissionsCompanion(state: Value('pending_validation')),
    );

    expect(await repository.unsyncedDataCount(), 0);
  });
}
