import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/journal/data/journal_service.dart';
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
    repo = TransportRepositoryImpl(db, sync, JournalService(db));
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

    // Envoi unique : pas de sync à l'étape transbordement.
    expect(await sync.pending(), isEmpty);
  });

  test('persistChaine remplace la chaîne existante', () async {
    await repo.persistChaine(
        'MICA-2026-0001', [const Transbordement(ordre: 1)]);
    await repo.persistChaine('MICA-2026-0001',
        [const Transbordement(ordre: 1), const Transbordement(ordre: 2)]);
    final back = await repo.chaineFor('MICA-2026-0001');
    expect(back.length, 2);
  });

  test('persistChaine enregistre ET relit les photos', () async {
    await repo.persistChaine('MICA-2026-0001', [
      const Transbordement(
          ordre: 1,
          photoDechargePath: '/tmp/unload.jpg',
          photoRechargePath: '/tmp/reload.jpg'),
    ]);
    final back = await repo.chaineFor('MICA-2026-0001');
    expect(back.single.photoDechargePath, '/tmp/unload.jpg');
    expect(back.single.photoRechargePath, '/tmp/reload.jpg');
  });

  test('corriger un maillon ne perd pas les photos des autres', () async {
    await repo.persistChaine('MICA-2026-0001', [
      const Transbordement(ordre: 1, photoDechargePath: '/a.jpg'),
      const Transbordement(ordre: 2, photoDechargePath: '/b.jpg'),
    ]);
    // Relit, corrige le n°1, re-persiste (flux d'édition du détail).
    final chaine = await repo.chaineFor('MICA-2026-0001');
    final corrigee = chaine
        .map((m) => m.ordre == 1 ? m.copyWith(plaqueApres: 'X') : m)
        .toList();
    await repo.persistChaine('MICA-2026-0001', corrigee);

    final relu = await repo.chaineFor('MICA-2026-0001');
    expect(relu.map((m) => m.photoDechargePath), ['/a.jpg', '/b.jpg']);
    expect(relu.firstWhere((m) => m.ordre == 1).plaqueApres, 'X');
  });
}
