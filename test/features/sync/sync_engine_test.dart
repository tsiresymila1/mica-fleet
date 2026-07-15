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
  _FakeRemote({this.failTimes = 0, this.alwaysFail = false});

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
  int lastPhotoCount = 0;
  @override
  Future<void> uploadPhotos(String deviceUuid, List photos) async {
    uploadedFor.add(deviceUuid);
    lastPhotoCount = photos.length;
  }

  @override
  Future<List<RemoteMine>> fetchMines() async =>
      [RemoteMine('m1', 'Mine 1', -18.9, 47.5, 20, null, null, null, true)];
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
  });

  group('SyncEngine', () {
    test('push réussi marque synced', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();
      expect(remote.pushed, ['a']);
      expect(await store.pending(), isEmpty);
    });

    test('push échoué garde en base + incrémente attempts + backoff futur',
        () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      await SyncEngine(store, _FakeRemote(failTimes: 1), db).sync();
      final rows = await db.select(db.syncQueue).get();
      expect(rows.single.status, 'pending');
      expect(rows.single.attempts, 1);
      expect(rows.single.nextRetryAt, isNotNull);
      // Exclu de pending() tant que le backoff n'est pas échu.
      expect(await store.pending(), isEmpty);
    });

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
      final row = await (db.select(db.syncQueue)
            ..where((t) => t.opId.equals('a')))
          .getSingle();
      expect(row.status, 'synced');
      expect(row.odooId, 42);
      expect(row.syncedAt, isNotNull);
    });

    test('après 5 tentatives → statut failed (terminal)', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      // Simule 4 échecs déjà encaissés.
      await store.updateStatus('a', SyncStatus.pending, attempts: 4);
      await SyncEngine(store, _FakeRemote(alwaysFail: true), db).sync();
      final row = await (db.select(db.syncQueue)
            ..where((t) => t.opId.equals('a')))
          .getSingle();
      expect(row.status, 'failed');
      expect(row.attempts, 5);
    });

    test('après submit chargement : upload photos batch + purge fichier', () async {
      final tmp = File('${Directory.systemTemp.path}/mica_test_photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await db.into(db.chargements).insert(ChargementsCompanion.insert(
          id: 'C1',
          fournisseurId: 'F001',
          dateCreation: DateTime(2026),
          deviceUuid: const Value('uuid-1')));
      await db.into(db.mineChargements).insert(MineChargementsCompanion.insert(
          chargementId: 'C1',
          mineId: 'M001',
          photoPath: Value(tmp.path),
          photoHash: const Value('h')));
      await store.enqueue(SyncOperation(
          opId: 'op1',
          entityType: 'chargement',
          entityId: 'C1',
          opType: SyncOpType.create,
          payload: const {},
          createdAt: DateTime(2026, 1, 1)));

      final remote = _FakeRemote();
      await SyncEngine(store, remote, db).sync();

      expect(remote.uploadedFor, ['uuid-1']);
      expect(remote.lastPhotoCount, 1);
      final charg = await (db.select(db.chargements)
            ..where((t) => t.id.equals('C1')))
          .getSingle();
      expect(charg.photosUploaded, isTrue);
      expect(tmp.existsSync(), isFalse); // fichier purgé
    });

    test('pull insère les mines en local', () async {
      await SyncEngine(store, _FakeRemote(), db).sync();
      final mines = await db.select(db.mines).get();
      expect(mines.single.id, 'm1');
    });
  });
}
