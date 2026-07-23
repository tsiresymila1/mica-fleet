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

  /// Réserve une opération pour l'envoi de façon atomique : passe `pending` →
  /// `syncing` en une seule écriture conditionnelle. Renvoie `true` si CE
  /// process l'a réservée, `false` si un autre l'avait déjà prise (bouton
  /// manuel vs sync en arrière-plan) → évite le double envoi.
  Future<bool> claim(String opId);

  /// Remet les opérations bloquées en `syncing` (app tuée en plein push) vers
  /// `pending`. À appeler au démarrage.
  Future<void> resetInFlight();
}
