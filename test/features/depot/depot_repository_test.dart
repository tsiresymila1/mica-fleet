import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/depot/data/repositories/depot_repository_impl.dart';
import 'package:mica_fleet/features/depot/domain/entities/arrivee_depot.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';

void main() {
  late AppDatabase db;
  late DepotRepositoryImpl repo;
  late DriftLocalSyncStore sync;

  setUp(() async {
    db = AppDatabase.memory();
    sync = DriftLocalSyncStore(db);
    repo = DepotRepositoryImpl(db, sync);
    await db.into(db.depots).insert(DepotsCompanion.insert(
        id: 'D1', nom: 'Dépôt 1', lat: -18.9, lon: 47.5));
    await db.into(db.depots).insert(DepotsCompanion.insert(
        id: 'D2',
        nom: 'Inactif',
        lat: -19.0,
        lon: 47.6,
        actif: const Value(false)));
    await db.into(db.chargements).insert(ChargementsCompanion.insert(
        id: 'MICA-2026-0001',
        fournisseurId: 'F001',
        dateCreation: DateTime(2026)));
  });
  tearDown(() => db.close());

  test('activeDepots ne renvoie que les dépôts actifs', () async {
    final d = await repo.activeDepots();
    expect(d.map((x) => x.id).toList(), ['D1']);
  });

  test('persistArrivee enregistre et journalise la sync', () async {
    final r = await repo.persistArrivee(const ArriveeDepot(
        chargementId: 'MICA-2026-0001',
        depotId: 'D1',
        chauffeur: 'Jean',
        numPermis: 'P1',
        numLot: 'L1',
        gpsLat: -18.9,
        gpsLon: 47.5,
        statutGps: 'valide'));
    expect(r.isRight(), isTrue);

    final rows = await db.select(db.arriveesDepot).get();
    expect(rows.single.chauffeur, 'Jean');

    final pending = await sync.pending();
    expect(pending.single.entityType, 'arrivee_depot');
  });
}
