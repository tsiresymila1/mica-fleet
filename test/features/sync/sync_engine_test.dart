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
  _FakeRemote({this.failTimes = 0});

  @override
  Future<void> pushOperation(SyncOperation op) async {
    if (failTimes > 0) {
      failTimes--;
      throw Exception('net');
    }
    pushed.add(op.opId);
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

    test('push échoué garde pending + incrémente attempts', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      await SyncEngine(store, _FakeRemote(failTimes: 1), db).sync();
      final p = await store.pending();
      expect(p.single.attempts, 1);
    });

    test('même opId rejoué = pas de doublon distant', () async {
      await store.enqueue(_op('a', DateTime(2026, 1, 1)));
      final remote = _FakeRemote();
      final engine = SyncEngine(store, remote, db);
      await engine.sync();
      await engine.sync();
      expect(remote.pushed, ['a']);
    });

    test('pull insère les mines en local', () async {
      await SyncEngine(store, _FakeRemote(), db).sync();
      final mines = await db.select(db.mines).get();
      expect(mines.single.id, 'm1');
    });
  });
}
