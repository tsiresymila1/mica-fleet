import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';

/// Une ligne d'historique de synchronisation (une opération de la file).
class SyncHistoryItem {
  final String opId;
  final String entityType; // lot, chargement…
  final String entityId; // ex. MICA-2026-0007-L1
  final String status; // pending / syncing / synced / failed
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final DateTime? nextRetryAt;
  final int? odooId;
  const SyncHistoryItem({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.status,
    required this.attempts,
    required this.lastError,
    required this.createdAt,
    required this.syncedAt,
    required this.nextRetryAt,
    required this.odooId,
  });
}

/// Historique de sync : opérations les plus récentes d'abord.
final syncHistoryProvider =
    FutureProvider.autoDispose<List<SyncHistoryItem>>((ref) async {
  final db = ref.watch(dbProvider);
  final rows = await (db.select(db.syncQueue)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .get();
  return rows
      .map((r) => SyncHistoryItem(
            opId: r.opId,
            entityType: r.entityType,
            entityId: r.entityId,
            status: r.status,
            attempts: r.attempts,
            lastError: r.lastError,
            createdAt: r.createdAt,
            syncedAt: r.syncedAt,
            nextRetryAt: r.nextRetryAt,
            odooId: r.odooId,
          ))
      .toList();
});
