import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';
import '../domain/repositories/remote_data_source.dart';

class SyncEngine {
  final LocalSyncStore store;
  final RemoteDataSource remote;
  final AppDatabase db;
  SyncEngine(this.store, this.remote, this.db);

  /// Push FIFO des pending puis pull du référentiel mines.
  Future<void> sync() async {
    final ops = await store.pending();
    for (final op in ops) {
      await store.updateStatus(op.opId, SyncStatus.syncing);
      try {
        await remote.pushOperation(op);
        await store.updateStatus(op.opId, SyncStatus.synced);
      } catch (e) {
        await store.updateStatus(op.opId, SyncStatus.pending,
            attempts: op.attempts + 1,
            lastError: e.toString(),
            nextRetryAt: _backoff(op.attempts + 1));
      }
    }
    await _pullMines();
  }

  Future<void> _pullMines() async {
    final mines = await remote.fetchMines();
    await db.batch((b) {
      for (final m in mines) {
        b.insert(
          db.mines,
          MinesCompanion.insert(
            id: m.id,
            nom: m.nom,
            lat: m.lat,
            lon: m.lon,
            rayonMetres: Value(m.rayonMetres),
            district: Value(m.district),
            commune: Value(m.commune),
            region: Value(m.region),
            actif: Value(m.actif),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  DateTime _backoff(int attempts) {
    final seconds = (attempts * attempts * 5).clamp(5, 600);
    return DateTime.now().add(Duration(seconds: seconds));
  }
}
