import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';

class DriftLocalSyncStore implements LocalSyncStore {
  final AppDatabase db;
  DriftLocalSyncStore(this.db);

  @override
  Future<void> enqueue(SyncOperation op) async {
    await db.into(db.syncQueue).insertOnConflictUpdate(
          SyncQueueCompanion.insert(
            opId: op.opId,
            entityType: op.entityType,
            entityId: op.entityId,
            opType: op.opType.name,
            payload: jsonEncode(op.payload),
            createdAt: op.createdAt,
            status: Value(op.status.name),
            attempts: Value(op.attempts),
            agentLogin: Value(op.agentLogin),
            gpsLat: Value(op.gpsLat),
            gpsLon: Value(op.gpsLon),
            gpsAccuracy: Value(op.gpsAccuracy),
          ),
        );
  }

  @override
  Future<List<SyncOperation>> pending() async {
    final now = DateTime.now();
    final q = db.select(db.syncQueue)
      ..where((t) =>
          t.status.equals('pending') &
          (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(now)))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(10); // batch max 10 par exécution
    final rows = await q.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<bool> claim(String opId) async {
    // UPDATE ... WHERE status='pending' : atomique côté SQLite. Le nombre de
    // lignes modifiées dit si on a gagné la course (1) ou non (0).
    final n = await (db.update(db.syncQueue)
          ..where((t) => t.opId.equals(opId) & t.status.equals('pending')))
        .write(const SyncQueueCompanion(status: Value('syncing')));
    return n > 0;
  }

  @override
  Future<void> resetInFlight() async {
    await (db.update(db.syncQueue)..where((t) => t.status.equals('syncing')))
        .write(const SyncQueueCompanion(status: Value('pending')));
  }

  @override
  Future<void> updateStatus(String opId, SyncStatus status,
      {int? attempts,
      String? lastError,
      DateTime? nextRetryAt,
      int? odooId,
      DateTime? syncedAt}) async {
    await (db.update(db.syncQueue)..where((t) => t.opId.equals(opId))).write(
      SyncQueueCompanion(
        status: Value(status.name),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        lastError: Value(lastError),
        nextRetryAt: Value(nextRetryAt),
        odooId: odooId == null ? const Value.absent() : Value(odooId),
        syncedAt: syncedAt == null ? const Value.absent() : Value(syncedAt),
      ),
    );
  }

  SyncOperation _toEntity(SyncQueueRow r) => SyncOperation(
        opId: r.opId,
        entityType: r.entityType,
        entityId: r.entityId,
        opType: SyncOpType.values.byName(r.opType),
        payload: jsonDecode(r.payload) as Map<String, dynamic>,
        status: SyncStatus.values.byName(r.status),
        attempts: r.attempts,
        lastError: r.lastError,
        createdAt: r.createdAt,
        nextRetryAt: r.nextRetryAt,
        odooId: r.odooId,
        syncedAt: r.syncedAt,
        agentLogin: r.agentLogin,
        gpsLat: r.gpsLat,
        gpsLon: r.gpsLon,
        gpsAccuracy: r.gpsAccuracy,
      );
}
