import '../entities/sync_operation.dart';

abstract class LocalSyncStore {
  Future<void> enqueue(SyncOperation op);

  /// Opérations à pousser : `pending` dont le backoff (`nextRetryAt`) est échu,
  /// en FIFO par createdAt.
  Future<List<SyncOperation>> pending();

  Future<void> updateStatus(String opId, SyncStatus status,
      {int? attempts,
      String? lastError,
      DateTime? nextRetryAt,
      int? odooId,
      DateTime? syncedAt});

  /// Remet les opérations bloquées en `syncing` (app tuée en plein push) vers
  /// `pending`. À appeler au démarrage.
  Future<void> resetInFlight();
}
