import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/sync/data/sync_engine.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';

SyncOperation _op(String id, DateTime at) => SyncOperation(
  opId: id,
  entityType: 'chargement',
  entityId: 'MICA-2026-0001',
  opType: SyncOpType.create,
  payload: const {'k': 'v'},
  createdAt: at,
);

class _FakeRemote implements RemoteDataSource {
  final List<String> pushed = [];
  int failTimes;
  final bool alwaysFail;
  final String? failPhotoKey;
  _FakeRemote({this.failTimes = 0, this.alwaysFail = false, this.failPhotoKey});

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    if (alwaysFail || failTimes > 0) {
      failTimes--;
      throw Exception('net');
    }
    pushed.add(op.opId);
    return 42; // faux odoo_id
  }

  final List<String> uploadedFor = [];
  final List<String> uploadedPayloads = [];
  final List<PhotoPart> uploadedPhotos = [];
  @override
  Future<void> uploadPhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    if (photo.key == failPhotoKey) throw Exception('photo net');
    uploadedFor.add(deviceUuid);
    uploadedPayloads.add(payloadId);
    uploadedPhotos.add(photo);
  }

  @override
  Future<List<RemoteMine>> fetchMines() async => [
    RemoteMine('m1', 'Mine 1', -18.9, 47.5, 20, null, null, null, true),
  ];
}

void main() {
  late AppDatabase db;
  late DriftLocalSyncStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = DriftLocalSyncStore(db);
  });
  tearDown(() => db.close());

  group('DriftLocalSyncStore', () {
    test('enqueue puis pending renvoie en FIFO', () async {
      await store.enqueue(_op('b', DateTime(2026, 1, 2)));
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final p = await store.pending();
      expect(p.map((o) => o.opId).toList(), ['a', 'b']);
    });

    test('updateStatus synced retire de pending', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      await store.updateStatus('a', SyncStatus.synced);
      expect(await store.pending(), isEmpty);
    });

    test(
      'claim réussit une fois, échoue au second appel (anti double-envoi)',
      () async {
        await store.enqueue(_op('a', DateTime(2026, 1, 1)));
        expect(await store.claim('a'), isTrue); // ce process réserve
        expect(await store.claim('a'), isFalse); // déjà syncing → refusé
      },
    );
  });

  group('SyncEngine', () {
    test('push réussi marque synced', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();
      expect(remote.pushed, ['a']);
      expect(await store.pending(), isEmpty);
    });

    test(
      'push échoué garde en base + incrémente attempts + backoff futur',
      () async {
        await store.enqueue(_op('a', DateTime(2026, 1, 1)));
        await SyncEngine(store, _FakeRemote(failTimes: 1), db).sync();
        final rows = await db.select(db.syncQueue).get();
        expect(rows.single.status, 'pending');
        expect(rows.single.attempts, 1);
        expect(rows.single.nextRetryAt, isNotNull);
        // Exclu de pending() tant que le backoff n'est pas échu.
        expect(await store.pending(), isEmpty);
      },
    );

    test('resetInFlight remet les syncing en pending', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      await store.updateStatus('a', SyncStatus.syncing);
      expect(await store.pending(), isEmpty);
      await store.resetInFlight();
      expect((await store.pending()).single.opId, 'a');
    });

    test('même opId rejoué = pas de doublon distant', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      final engine = SyncEngine(store, remote, db);
      await engine.sync();
      await engine.sync();
      expect(remote.pushed, ['a']);
    });

    test('push réussi enregistre odoo_id + syncedAt', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      await SyncEngine(store, _FakeRemote(), db).sync();
      final row = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('a'))).getSingle();
      expect(row.status, 'synced');
      expect(row.odooId, 42);
      expect(row.syncedAt, isNotNull);
    });

    test('après 5 tentatives → statut failed (terminal)', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      // Simule 4 échecs déjà encaissés.
      await store.updateStatus('a', SyncStatus.pending, attempts: 4);
      await SyncEngine(store, _FakeRemote(alwaysFail: true), db).sync();
      final row = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('a'))).getSingle();
      expect(row.status, 'failed');
      expect(row.attempts, 5);
    });

    test(
      'après submit lot : upload une photo à la fois + purge fichier',
      () async {
        final tmp = File('${Directory.systemTemp.path}/mica_test_photo.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: 'C1',
                fournisseurId: 'F001',
                dateCreation: DateTime(2026),
              ),
            );
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'C1-L1',
                sessionId: 'C1',
                mineId: 'M001',
                photoPath: Value(tmp.path),
                photoHash: const Value('h'),
                deviceUuid: const Value('uuid-1'),
              ),
            );
        await store.enqueue(
          SyncOperation(
            opId: 'op1',
            entityType: 'lot',
            entityId: 'C1-L1',
            opType: SyncOpType.create,
            payload: const {'id': 'payload-uuid-1'},
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        final remote = _FakeRemote();
        await SyncEngine(store, remote, db).sync();

        expect(remote.uploadedFor, ['uuid-1']);
        expect(remote.uploadedPayloads, ['payload-uuid-1']);
        expect(remote.uploadedPhotos.single.key, 'mine');
        expect(remote.uploadedPhotos.single.hash, 'h');
        final lot = await (db.select(
          db.lots,
        )..where((t) => t.id.equals('C1-L1'))).getSingle();
        expect(lot.photosUploaded, isTrue);
        expect(tmp.existsSync(), isFalse); // fichier purgé
      },
    );

    test('calcule le hash manquant avant un upload unitaire', () async {
      final tmp = File('${Directory.systemTemp.path}/mica_test_arrival.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await db
          .into(db.chargements)
          .insert(
            ChargementsCompanion.insert(
              id: 'C2',
              fournisseurId: 'F001',
              dateCreation: DateTime(2026),
            ),
          );
      await db
          .into(db.lots)
          .insert(
            LotsCompanion.insert(
              id: 'C2-L1',
              sessionId: 'C2',
              mineId: 'M001',
              deviceUuid: const Value('uuid-2'),
            ),
          );
      await db
          .into(db.arriveesDepot)
          .insert(
            ArriveesDepotCompanion.insert(
              lotId: 'C2-L1',
              depotId: 'D1',
              chauffeur: 'Jean',
              numPermis: 'P1',
              numLot: 'L1',
              gpsLat: -18.9,
              gpsLon: 47.5,
              photoArriveePath: Value(tmp.path),
              statutGps: 'valide',
            ),
          );
      await store.enqueue(
        SyncOperation(
          opId: 'op2',
          entityType: 'lot',
          entityId: 'C2-L1',
          opType: SyncOpType.create,
          payload: const {'id': 'payload-uuid-2'},
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();

      expect(remote.uploadedPhotos.single.key, 'arrival');
      expect(
        remote.uploadedPhotos.single.hash,
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      );
      expect(tmp.existsSync(), isFalse);
    });

    test('un échec partiel reprend uniquement les photos restantes', () async {
      final mine = File('${Directory.systemTemp.path}/mica_partial_mine.jpg')
        ..writeAsBytesSync([1]);
      final arrival = File(
        '${Directory.systemTemp.path}/mica_partial_arrival.jpg',
      )..writeAsBytesSync([2]);
      await db
          .into(db.chargements)
          .insert(
            ChargementsCompanion.insert(
              id: 'C3',
              fournisseurId: 'F001',
              dateCreation: DateTime(2026),
            ),
          );
      await db
          .into(db.lots)
          .insert(
            LotsCompanion.insert(
              id: 'C3-L1',
              sessionId: 'C3',
              mineId: 'M001',
              photoPath: Value(mine.path),
              photoHash: const Value('mine-hash'),
              deviceUuid: const Value('uuid-3'),
            ),
          );
      await db
          .into(db.arriveesDepot)
          .insert(
            ArriveesDepotCompanion.insert(
              lotId: 'C3-L1',
              depotId: 'D1',
              chauffeur: 'Jean',
              numPermis: 'P1',
              numLot: 'L1',
              gpsLat: -18.9,
              gpsLon: 47.5,
              photoArriveePath: Value(arrival.path),
              statutGps: 'valide',
            ),
          );
      await store.enqueue(
        SyncOperation(
          opId: 'op3',
          entityType: 'lot',
          entityId: 'C3-L1',
          opType: SyncOpType.create,
          payload: const {'id': 'payload-uuid-3'},
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final firstRemote = _FakeRemote(failPhotoKey: 'arrival');
      await SyncEngine(store, firstRemote, db).sync();

      expect(firstRemote.uploadedPhotos.map((p) => p.key), ['mine']);
      expect(mine.existsSync(), isFalse);
      expect(arrival.existsSync(), isTrue);
      var lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isFalse);

      final retryRemote = _FakeRemote();
      await SyncEngine(store, retryRemote, db).sync();

      expect(retryRemote.uploadedPhotos.map((p) => p.key), ['arrival']);
      expect(arrival.existsSync(), isFalse);
      lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isTrue);
    });

    test('pull insère les mines en local', () async {
      await SyncEngine(store, _FakeRemote(), db).sync();
      final mines = await db.select(db.mines).get();
      expect(mines.single.id, 'm1');
    });
  });
}
