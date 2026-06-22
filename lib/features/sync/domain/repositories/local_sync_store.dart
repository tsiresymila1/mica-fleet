import '../entities/sync_operation.dart';

abstract class LocalSyncStore {
  Future<void> enqueue(SyncOperation op);
  Future<List<SyncOperation>> pending(); // FIFO par createdAt
  Future<void> updateStatus(String opId, SyncStatus status,
      {int? attempts, String? lastError, DateTime? nextRetryAt});
}
