import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mica_fleet/core/db/app_database.dart';
import 'package:mica_fleet/features/sync/data/local_sync_store_impl.dart';
import 'package:mica_fleet/features/sync/data/sync_engine.dart';
import 'package:mica_fleet/features/mines/data/repositories/mine_submission_repository_impl.dart';
import 'package:mica_fleet/features/capture/domain/entities/captured_photo.dart';
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
  final List<RemoteMine> mines;
  final List<RemoteDepot> depots;
  final List<RemoteLot> lots;
  _FakeRemote({
    this.failTimes = 0,
    this.alwaysFail = false,
    this.failPhotoKey,
    this.pushError,
    List<RemoteMine>? mines,
    List<RemoteDepot>? depots,
    List<RemoteLot>? lots,
  }) : mines =
           mines ??
           [
             RemoteMine(
               'm1',
               'Mine 1',
               -18.9,
               47.5,
               20,
               null,
               null,
               null,
               true,
             ),
           ],
       depots = depots ?? [RemoteDepot('d1', 'Dépôt 1', -18.8, 47.4, 20, true)],
       lots = lots ?? const [];

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
  final List<PhotoPart> uploadedMinePhotos = [];
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
  Future<void> uploadMinePhoto(
    String deviceUuid,
    String payloadId,
    PhotoPart photo,
  ) async {
    if (photo.key == failPhotoKey) throw Exception('mine photo net');
    uploadedFor.add(deviceUuid);
    uploadedPayloads.add(payloadId);
    uploadedMinePhotos.add(photo);
  }

  @override
  Future<List<RemoteMine>> fetchMines() async => mines;

  @override
  Future<List<RemoteDepot>> fetchDepots() async => depots;

  @override
  Future<List<RemoteLot>> fetchLots() async => lots;

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
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
      'après submit lot : upload unitaire et conservation du fichier',
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
        expect(tmp.existsSync(), isTrue); // conservé pour le détail du lot
        expect(jsonDecode(lot.uploadedPhotoKeys), ['mine']);
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

    test('upload v2 envoie les six clés mine et dépôt une par une', () async {
      final directory = Directory.systemTemp.createTempSync('mica_v2_upload_');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      await db
          .into(db.chargements)
          .insert(
            ChargementsCompanion.insert(
              id: 'V2',
              fournisseurId: 'F001',
              dateCreation: DateTime(2026),
            ),
          );
      await db
          .into(db.lots)
          .insert(
            LotsCompanion.insert(
              id: 'V2-L1',
              sessionId: 'V2',
              mineId: 'M001',
              deviceUuid: const Value('v2-device'),
              photoSchemaVersion: const Value(2),
            ),
          );
      for (final stage in ['mine', 'depot_unload']) {
        for (final role in ['plate', 'mica', 'truck_with_mica']) {
          final file = File('${directory.path}/${stage}_$role.jpg')
            ..writeAsBytesSync([stage.length, role.length]);
          await db
              .into(db.lotTraceabilityPhotos)
              .insert(
                LotTraceabilityPhotosCompanion.insert(
                  lotId: 'V2-L1',
                  stage: stage,
                  role: role,
                  path: file.path,
                  hash: 'hash-$stage-$role',
                  lat: -18.9,
                  lon: 47.5,
                  gpsAccuracy: 3,
                  capturedAt: DateTime.utc(2026, 8, 13),
                ),
              );
        }
      }
      await store.enqueue(
        SyncOperation(
          opId: 'v2-device',
          entityType: 'lot',
          entityId: 'V2-L1',
          opType: SyncOpType.create,
          payload: const {
            'id': '44444444-4444-4444-8444-444444444444',
            'session_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'photo_schema_version': 2,
          },
          createdAt: DateTime(2026),
        ),
      );

      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();

      expect(remote.uploadedPhotos.map((photo) => photo.key).toSet(), {
        'mine_plate',
        'mine_mica',
        'mine_truck_with_mica',
        'depot_unload_plate',
        'depot_unload_mica',
        'depot_unload_truck_with_mica',
      });
      expect(remote.uploadedPhotos, hasLength(6));
      expect(directory.listSync().whereType<File>(), hasLength(6));
    });

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
              depotId: const Value('D1'),
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
      expect(tmp.existsSync(), isTrue);
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
              depotId: const Value('D1'),
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
      expect(mine.existsSync(), isTrue);
      expect(arrival.existsSync(), isTrue);
      var lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isFalse);
      expect(jsonDecode(lot.uploadedPhotoKeys), ['mine']);
      var op = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('op3'))).getSingle();
      expect(op.lastError, contains('Échec de la photo « arrival »'));
      expect(op.lastError, contains('photo net'));

      final retryRemote = _FakeRemote();
      await SyncEngine(store, retryRemote, db).sync();

      expect(retryRemote.uploadedPhotos.map((p) => p.key), ['arrival']);
      expect(mine.existsSync(), isTrue);
      expect(arrival.existsSync(), isTrue);
      lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals('C3-L1'))).getSingle();
      expect(lot.photosUploaded, isTrue);
      expect(jsonDecode(lot.uploadedPhotoKeys), ['mine', 'arrival']);
      op = await (db.select(
        db.syncQueue,
      )..where((t) => t.opId.equals('op3'))).getSingle();
      expect(op.lastError, isNull);
    });

    test('pull rafraîchit mines et dépôts sans doublon', () async {
      await db
          .into(db.mines)
          .insert(
            MinesCompanion.insert(
              id: 'ancienne-mine',
              nom: 'Ancienne mine',
              lat: -18,
              lon: 47,
            ),
          );
      await db
          .into(db.depots)
          .insert(
            DepotsCompanion.insert(
              id: 'ancien-depot',
              nom: 'Ancien dépôt',
              lat: -18,
              lon: 47,
            ),
          );
      await db
          .into(db.communes)
          .insert(
            CommunesCompanion.insert(
              id: const Value(1),
              nom: 'Ancienne commune',
            ),
          );
      final engine = SyncEngine(store, _FakeRemote(), db);
      await engine.sync();
      await engine.sync();

      final mines = await db.select(db.mines).get();
      expect(mines, hasLength(2));
      expect(mines.singleWhere((row) => row.id == 'm1').actif, isTrue);
      expect(
        mines.singleWhere((row) => row.id == 'ancienne-mine').actif,
        isFalse,
      );
      final depots = await db.select(db.depots).get();
      expect(depots, hasLength(2));
      expect(depots.singleWhere((row) => row.id == 'd1').actif, isTrue);
      expect(
        depots.singleWhere((row) => row.id == 'ancien-depot').actif,
        isFalse,
      );
      // Les communes ne sont plus utilisées par le formulaire mine. L'ancien
      // cache reste intact afin de ne pas rendre la migration destructive.
      final communes = await db.select(db.communes).get();
      expect(communes, hasLength(1));
      expect(communes.single.id, 1);
    });

    test(
      'pull lots restaure le cache sans doublon et actualise la validation',
      () async {
        final remoteLot = RemoteLot(
          payloadId: 'payload-server-1',
          sessionId: 'session-server-1',
          reference: 'MICA-2026-0042',
          validationStatus: 'validated',
          validationReason: null,
          createdAt: DateTime.utc(2026, 8, 14, 8),
          updatedAt: DateTime.utc(2026, 8, 14, 10),
          mineId: 'm1',
          mineName: 'Mine 1',
          color: 'Blanc',
          estimatedQuantity: 120,
          transportStatus: 'arrive',
          score: 96,
        );
        final engine = SyncEngine(store, _FakeRemote(lots: [remoteLot]), db);

        await engine.sync();
        await engine.sync();

        final lots = await db.select(db.lots).get();
        expect(lots, hasLength(1));
        expect(lots.single.payloadUuid, 'payload-server-1');
        expect(lots.single.serverReference, 'MICA-2026-0042');
        expect(lots.single.validationStatus, 'validated');
        expect(lots.single.remoteOnly, isTrue);
        expect(lots.single.score, 96);
      },
    );

    test(
      'pull lots supprime les lots synchronisés qui n’existent plus serveur',
      () async {
        await db.into(db.fournisseurs).insert(
          FournisseursCompanion.insert(
            id: 'eddy',
            nom: 'Eddy',
            actif: const Value(true),
            sessionToken: const Value('token-sync-lot'),
          ),
        );
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: 'S-2026-0001',
                fournisseurId: 'eddy',
                dateCreation: DateTime(2026),
              ),
            );
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'S-2026-0001-L1',
                payloadUuid: const Value('payload-existing'),
                sessionId: 'S-2026-0001',
                mineId: 'm1',
                statut: const Value('arrive'),
              ),
            );
        await store.enqueue(
          SyncOperation(
            opId: 'sync-lot-1',
            entityType: 'lot',
            entityId: 'S-2026-0001-L1',
            opType: SyncOpType.create,
            payload: const {
              'id': 'payload-existing',
              'session_id': 'session-existing',
            },
            createdAt: DateTime(2026, 8, 14, 8),
          ),
        );
        await store.updateStatus('sync-lot-1', SyncStatus.synced);

        final engine = SyncEngine(store, _FakeRemote(lots: const []), db);
        await engine.sync();

        final lots = await db.select(db.lots).get();
        expect(lots, isEmpty);
      },
    );

    test(
      'pull lots ne supprime pas les lots locaux non synchronisés',
      () async {
        await db.into(db.fournisseurs).insert(
          FournisseursCompanion.insert(
            id: 'eddy',
            nom: 'Eddy',
            actif: const Value(true),
            sessionToken: const Value('token-local-lot'),
          ),
        );
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: 'S-2026-0002',
                fournisseurId: 'eddy',
                dateCreation: DateTime(2026),
              ),
            );
        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'S-2026-0002-L1',
                payloadUuid: const Value('payload-local-only'),
                sessionId: 'S-2026-0002',
                mineId: 'm1',
                statut: const Value('en_cours'),
              ),
            );

        final engine = SyncEngine(store, _FakeRemote(lots: const []), db);
        await engine.sync();

        final lots = await db.select(db.lots).get();
        expect(lots, hasLength(1));
        expect(lots.single.id, 'S-2026-0002-L1');
      },
    );

    test(
      'proposition mine : submit, 5 uploads puis ajout après approbation',
      () async {
        final storage = Directory.systemTemp.createTempSync(
          'mica_submission_storage_',
        );
        final files = <File>[];
        final photos = <CapturedPhoto>[];
        for (var i = 1; i <= 5; i++) {
          final file = File(
            '${Directory.systemTemp.path}/mica_submission_position_$i.jpg',
          )..writeAsBytesSync([i]);
          files.add(file);
          photos.add(
            CapturedPhoto(
              path: file.path,
              sha256: 'hash-$i',
              lat: -18.91 + i / 10000,
              lon: 47.52 + i / 10000,
              precision: 4,
              takenAt: DateTime.utc(2026, 7, 30, 8, i),
            ),
          );
        }
        addTearDown(() {
          for (final file in files) {
            if (file.existsSync()) file.deleteSync();
          }
          if (storage.existsSync()) storage.deleteSync(recursive: true);
        });
        final created = await MineSubmissionRepositoryImpl(
          db,
          storageDirectory: () async => storage,
        ).create(name: 'Mine terrain', photos: photos, agentLogin: 'eddy');
        expect(created.isRight(), isTrue);
        final storedPaths = (await db.select(db.mineSubmissionPhotos).get())
            .map((row) => row.path)
            .toList();

        final remote = _FakeRemote(
          mines: [
            RemoteMine(
              '42',
              'Mine approuvée',
              -18.91,
              47.52,
              20,
              null,
              'Andilana',
              null,
              true,
            ),
          ],
        );
        await SyncEngine(store, remote, db).sync();

        expect(remote.pushedOperations.single.entityType, 'mine_submission');
        expect(remote.uploadedMinePhotos, hasLength(5));
        expect(remote.uploadedMinePhotos.map((p) => p.key), [
          'position_1',
          'position_2',
          'position_3',
          'position_4',
          'position_5',
        ]);
        final submission = (await db.select(db.mineSubmissions).get()).single;
        expect(submission.state, 'approved');
        expect(submission.approvedMineId, '42');
        final approved = await (db.select(
          db.mines,
        )..where((t) => t.id.equals('42'))).getSingle();
        expect(approved.nom, 'Mine approuvée');
        expect(storedPaths.every((path) => File(path).existsSync()), isTrue);
        expect(files.every((file) => !file.existsSync()), isTrue);
      },
    );

    test(
      'un échec photo mine reprend uniquement les preuves restantes',
      () async {
        final storage = Directory.systemTemp.createTempSync(
          'mica_mine_retry_storage_',
        );
        final files = <File>[];
        final photos = <CapturedPhoto>[];
        for (var i = 1; i <= 5; i++) {
          final file = File(
            '${Directory.systemTemp.path}/mica_mine_retry_position_$i.jpg',
          )..writeAsBytesSync([i]);
          files.add(file);
          photos.add(
            CapturedPhoto(
              path: file.path,
              sha256: 'retry-hash-$i',
              lat: -18.91,
              lon: 47.52,
              precision: 4,
              takenAt: DateTime.utc(2026, 7, 30, 9, i),
            ),
          );
        }
        addTearDown(() {
          for (final file in files) {
            if (file.existsSync()) file.deleteSync();
          }
          if (storage.existsSync()) storage.deleteSync(recursive: true);
        });
        await MineSubmissionRepositoryImpl(
          db,
          storageDirectory: () async => storage,
        ).create(name: 'Mine reprise', photos: photos, agentLogin: 'eddy');

        final firstRemote = _FakeRemote(failPhotoKey: 'position_3');
        await SyncEngine(store, firstRemote, db).sync();
        expect(firstRemote.uploadedMinePhotos.map((photo) => photo.key), [
          'position_1',
          'position_2',
        ]);
        var rows = await (db.select(
          db.mineSubmissionPhotos,
        )..orderBy([(t) => OrderingTerm.asc(t.key)])).get();
        expect(rows.map((row) => row.uploaded), [
          true,
          true,
          false,
          false,
          false,
        ]);

        final retryRemote = _FakeRemote(
          mines: [
            RemoteMine(
              '42',
              'Mine reprise validée',
              -18.91,
              47.52,
              20,
              null,
              'Andilana',
              null,
              true,
            ),
          ],
        );
        await SyncEngine(store, retryRemote, db).sync();
        expect(retryRemote.uploadedMinePhotos.map((photo) => photo.key), [
          'position_3',
          'position_4',
          'position_5',
        ]);
        final submission = (await db.select(db.mineSubmissions).get()).single;
        expect(submission.state, 'approved');
      },
    );

    test('une proposition absente du GET mine reste en attente', () async {
      final now = DateTime.utc(2026, 7, 30);
      await db
          .into(db.mineSubmissions)
          .insert(
            MineSubmissionsCompanion.insert(
              payloadId: 'rejected-payload',
              deviceUuid: 'rejected-device',
              nom: 'Mine en attente',
              state: const Value('pending_validation'),
              serverId: const Value(99),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await store.enqueue(
        SyncOperation(
          opId: 'rejected-device',
          entityType: 'mine_submission',
          entityId: 'rejected-payload',
          opType: SyncOpType.create,
          payload: const {'id': 'rejected-payload'},
          createdAt: now,
        ),
      );
      await store.updateStatus('rejected-device', SyncStatus.synced);

      await SyncEngine(store, _FakeRemote(), db).sync();

      final submission = (await db.select(db.mineSubmissions).get()).single;
      expect(submission.state, 'pending_validation');
      expect(submission.rejectionReason, isNull);
      expect(
        await (db.select(
          db.mines,
        )..where((t) => t.id.equals('99'))).getSingleOrNull(),
        isNull,
      );
    });

    test('envoi manuel force une proposition en échec et ses photos', () async {
      final photo = File(
        '${Directory.systemTemp.path}/mica_manual_mine_send.jpg',
      )..writeAsBytesSync([1, 2, 3]);
      addTearDown(() {
        if (photo.existsSync()) photo.deleteSync();
      });
      final now = DateTime.utc(2026, 8, 5);
      await db
          .into(db.mineSubmissions)
          .insert(
            MineSubmissionsCompanion.insert(
              payloadId: 'manual-payload',
              deviceUuid: 'manual-device',
              nom: 'Mine manuelle',
              state: const Value('local_pending'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.mineSubmissionPhotos)
          .insert(
            MineSubmissionPhotosCompanion.insert(
              payloadId: 'manual-payload',
              key: 'position_1',
              path: photo.path,
              hash: 'manual-hash',
              lat: -18.91,
              lon: 47.52,
              gpsAccuracy: 4,
              capturedAt: now,
            ),
          );
      await store.enqueue(
        SyncOperation(
          opId: 'manual-device',
          entityType: 'mine_submission',
          entityId: 'manual-payload',
          opType: SyncOpType.create,
          payload: const {'id': 'manual-payload', 'name': 'Mine manuelle'},
          createdAt: now,
        ),
      );
      await store.updateStatus(
        'manual-device',
        SyncStatus.failed,
        attempts: 5,
        lastError: 'ancien échec',
        nextRetryAt: now.add(const Duration(days: 1)),
      );
      final remote = _FakeRemote();

      final result = await SyncEngine(
        store,
        remote,
        db,
      ).sendMineSubmissionNow('manual-payload');

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(remote.pushed, ['manual-device']);
      expect(remote.uploadedMinePhotos.map((part) => part.key), ['position_1']);
      final submission = (await db.select(db.mineSubmissions).get()).single;
      expect(submission.state, 'pending_validation');
      final op = (await db.select(db.syncQueue).get()).single;
      expect(op.status, 'synced');
      expect(op.attempts, 0);
      expect(op.lastError, isNull);
    });
  });
}
