import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/sync/data/sync_engine.dart';
import 'package:mica_fleet/features/sync/domain/entities/sync_operation.dart';
import 'package:mica_fleet/features/sync/domain/repositories/remote_data_source.dart';
import 'package:uuid/uuid.dart';

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
  final List<SyncOperation> pushedOperations = [];
  int failTimes;
  final bool alwaysFail;
  final String? failPhotoKey;
  final Object? pushError;
  _FakeRemote({
    this.failTimes = 0,
    this.alwaysFail = false,
    this.failPhotoKey,
    this.pushError,
  });

  @override
  Future<int?> pushOperation(SyncOperation op) async {
    if (pushError != null) throw pushError!;
    if (alwaysFail || failTimes > 0) {
      failTimes--;
      throw Exception('net');
    }
    pushed.add(op.opId);
    pushedOperations.add(op);
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

    test(
      'un HTTP 500 stocke le corps serveur au lieu du message Dio',
      () async {
        await store.enqueue(_op('http-500', DateTime(2026, 1, 1)));
        final request = RequestOptions(
          path: '/api/tracking/submit',
          method: 'POST',
        );
        final error = DioException.badResponse(
          statusCode: 500,
          requestOptions: request,
          response: Response<dynamic>(
            requestOptions: request,
            statusCode: 500,
            data: {'status': 'error', 'message': 'Erreur Odoo détaillée'},
          ),
        );

        await SyncEngine(store, _FakeRemote(pushError: error), db).sync();

        final row = await (db.select(
          db.syncQueue,
        )..where((t) => t.opId.equals('http-500'))).getSingle();
        expect(row.lastError, contains('HTTP 500'));
        expect(row.lastError, contains('Erreur Odoo détaillée'));
        expect(row.lastError, isNot(contains('validateStatus')));
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

    test(
      'une ancienne op pending sans UUID reçoit des UUID persistés',
      () async {
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: 'MICA-2026-0007',
                fournisseurId: 'F001',
                dateCreation: DateTime(2026),
              ),
            );
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'MICA-2026-0007-L1',
                sessionId: 'MICA-2026-0007',
                mineId: 'M001',
              ),
            );
        await store.enqueue(
          SyncOperation(
            opId: 'migration-device-uuid',
            entityType: 'lot',
            entityId: 'MICA-2026-0007-L1',
            opType: SyncOpType.create,
            payload: const {
              'id': 'MICA-2026-0007-L1',
              'session_id': 'MICA-2026-0007',
            },
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        final remote = _FakeRemote();
        await SyncEngine(store, remote, db).sync();

        final submitted = remote.pushedOperations.single.payload;
        final payloadId = submitted['id'] as String;
        final sessionId = submitted['session_id'] as String;
        expect(Uuid.isValidUUID(fromString: payloadId), isTrue);
        expect(Uuid.isValidUUID(fromString: sessionId), isTrue);

        final lot = await (db.select(
          db.lots,
        )..where((t) => t.id.equals('MICA-2026-0007-L1'))).getSingle();
        final session = await (db.select(
          db.chargements,
        )..where((t) => t.id.equals('MICA-2026-0007'))).getSingle();
        expect(lot.payloadUuid, payloadId);
        expect(session.sessionUuid, sessionId);
      },
    );

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
            payload: const {
              'id': '11111111-1111-4111-8111-111111111111',
              'session_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            },
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        final remote = _FakeRemote();
        await SyncEngine(store, remote, db).sync();

        expect(remote.uploadedFor, ['uuid-1']);
        expect(remote.uploadedPayloads, [
          '11111111-1111-4111-8111-111111111111',
        ]);
        expect(
          remote.pushedOperations.single.payload['id'],
          '11111111-1111-4111-8111-111111111111',
        );
        expect(
          remote.pushedOperations.single.payload['session_id'],
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        );
        expect(remote.uploadedPhotos.single.key, 'mine');
        expect(remote.uploadedPhotos.single.hash, 'h');
        final lot = await (db.select(
          db.lots,
        )..where((t) => t.id.equals('C1-L1'))).getSingle();
        expect(lot.photosUploaded, isTrue);
        expect(tmp.existsSync(), isFalse); // fichier purgé
      },
    );

    test(
      'un ancien submit déjà synchronisé garde son payload_id pour les photos',
      () async {
        final tmp = File(
          '${Directory.systemTemp.path}/mica_legacy_synced_photo.jpg',
        )..writeAsBytesSync([1, 2, 3]);
        addTearDown(() {
          if (tmp.existsSync()) tmp.deleteSync();
        });
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: 'C-LEGACY',
                fournisseurId: 'F001',
                dateCreation: DateTime(2026),
              ),
            );
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'C-LEGACY-L1',
                sessionId: 'C-LEGACY',
                mineId: 'M001',
                photoPath: Value(tmp.path),
                photoHash: const Value('legacy-hash'),
                deviceUuid: const Value('legacy-device-uuid'),
              ),
            );
        await store.enqueue(
          SyncOperation(
            opId: 'legacy-device-uuid',
            entityType: 'lot',
            entityId: 'C-LEGACY-L1',
            opType: SyncOpType.create,
            payload: const {
              'id': 'legacy-payload-uuid',
              'session_id': 'legacy-session-uuid',
            },
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        await store.updateStatus('legacy-device-uuid', SyncStatus.synced);

        final remote = _FakeRemote();
        await SyncEngine(store, remote, db).sync();

        expect(remote.pushed, isEmpty);
        expect(remote.uploadedPayloads, ['legacy-payload-uuid']);
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
          payload: const {
            'id': '22222222-2222-4222-8222-222222222222',
            'session_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          },
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();

      expect(remote.uploadedPayloads, ['22222222-2222-4222-8222-222222222222']);
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
          payload: const {
            'id': '33333333-3333-4333-8333-333333333333',
            'session_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          },
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final firstRemote = _FakeRemote(failPhotoKey: 'arrival');
      await SyncEngine(store, firstRemote, db).sync();

      expect(firstRemote.uploadedPayloads, [
        '33333333-3333-4333-8333-333333333333',
      ]);
      expect(firstRemote.uploadedPhotos.map((p) => p.key), ['mine']);
      expect(mine.existsSync(), isFalse);
      expect(arrival.existsSync(), isTrue);
      var lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isFalse);
      var op = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('op3'))).getSingle();
      expect(op.lastError, contains('Échec de la photo « arrival »'));
      expect(op.lastError, contains('photo net'));

      final retryRemote = _FakeRemote();
      await SyncEngine(store, retryRemote, db).sync();

      expect(retryRemote.uploadedPhotos.map((p) => p.key), ['arrival']);
      expect(arrival.existsSync(), isFalse);
      lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isTrue);
      op = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('op3'))).getSingle();
      expect(op.lastError, isNull);
    });

    test('pull insère les mines en local', () async {
      await SyncEngine(store, _FakeRemote(), db).sync();
      final mines = await db.select(db.mines).get();
      expect(mines.single.id, 'm1');
    });
  });
}
