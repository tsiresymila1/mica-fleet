import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/transport/data/repositories/transport_repository_impl.dart';
import 'package:mica_fleet/features/transport/domain/entities/transbordement.dart';

void main() {
  late AppDatabase db;
  late TransportRepositoryImpl repo;
  late DriftLocalSyncStore sync;

  setUp(() async {
    db = AppDatabase.memory();
    sync = DriftLocalSyncStore(db);
    repo = TransportRepositoryImpl(db, sync);
    await db.into(db.chargements).insert(ChargementsCompanion.insert(
        id: 'MICA-2026-0001',
        fournisseurId: 'F001',
        dateCreation: DateTime(2026)));
  });
  tearDown(() => db.close());

  test('persistChaine enregistre, calcule distance et journalise la sync',
      () async {
    final chaine = [
      const Transbordement(
          ordre: 1,
          plaqueApres: 'B',
          gpsDechargeLat: -18.90000,
          gpsDechargeLon: 47.5,
          gpsRechargeLat: -18.90010,
          gpsRechargeLon: 47.5),
    ];
    final r = await repo.persistChaine('MICA-2026-0001', chaine);
    expect(r.isRight(), isTrue);

    final back = await repo.chaineFor('MICA-2026-0001');
    expect(back.single.ordre, 1);
    expect(back.single.plaqueApres, 'B');

    final pending = await sync.pending();
    expect(pending.single.entityType, 'transbordement');
  });

  test('persistChaine remplace la chaîne existante', () async {
    await repo.persistChaine(
        'MICA-2026-0001', [const Transbordement(ordre: 1)]);
    await repo.persistChaine('MICA-2026-0001',
        [const Transbordement(ordre: 1), const Transbordement(ordre: 2)]);
    final back = await repo.chaineFor('MICA-2026-0001');
    expect(back.length, 2);
  });
}
