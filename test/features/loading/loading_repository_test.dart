import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/journal/data/journal_service.dart';
import 'package:mica_fleet/features/loading/data/repositories/loading_repository_impl.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';

void main() {
  late AppDatabase db;
  late LoadingRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.memory();
    repo = LoadingRepositoryImpl(db, DriftLocalSyncStore(db), JournalService(db));
    await db.into(db.chargements).insert(ChargementsCompanion.insert(
        id: 'MICA-2026-0001',
        fournisseurId: 'F001',
        dateCreation: DateTime(2026)));
    await db.into(db.lots).insert(LotsCompanion.insert(
        id: 'MICA-2026-0001-L1',
        sessionId: 'MICA-2026-0001',
        mineId: 'M001'));
  });
  tearDown(() => db.close());

  test('supprime une session non arrivée + ses lots', () async {
    final r = await repo.deleteChargement('MICA-2026-0001');
    expect(r.isRight(), isTrue);
    expect(await db.select(db.chargements).get(), isEmpty);
    expect(await db.select(db.lots).get(), isEmpty);
  });

  test('refuse la suppression si un lot est arrivé au dépôt', () async {
    await db.into(db.depots).insert(
        DepotsCompanion.insert(id: 'D1', nom: 'D', lat: -18.9, lon: 47.5));
    await db.into(db.arriveesDepot).insert(ArriveesDepotCompanion.insert(
        lotId: 'MICA-2026-0001-L1',
        depotId: 'D1',
        chauffeur: 'J',
        numPermis: 'P',
        numLot: 'L',
        gpsLat: -18.9,
        gpsLon: 47.5,
        statutGps: 'valide'));
    final r = await repo.deleteChargement('MICA-2026-0001');
    expect(r.isLeft(), isTrue);
    expect(await db.select(db.chargements).get(), isNotEmpty);
  });
}
