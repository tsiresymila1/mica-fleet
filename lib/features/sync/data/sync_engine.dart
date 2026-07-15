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

  static const int maxAttempts = 5; // au-delà → statut failed (terminal)

  bool _running = false;

  /// Push FIFO des pending (backoff respecté) puis pull du référentiel.
  /// Ne lève jamais : les erreurs réseau laissent les opérations en attente.
  /// Réentrance protégée (déclenché à la fois par le réseau et le bouton).
  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      final ops = await store.pending(); // batch max 10
      for (final op in ops) {
        await store.updateStatus(op.opId, SyncStatus.syncing);
        try {
          final odooId = await remote.pushOperation(op);
          await store.updateStatus(op.opId, SyncStatus.synced,
              odooId: odooId, syncedAt: DateTime.now());
        } catch (e) {
          final attempts = op.attempts + 1;
          if (attempts >= maxAttempts) {
            // Échec terminal après N tentatives → intervention manuelle.
            await store.updateStatus(op.opId, SyncStatus.failed,
                attempts: attempts, lastError: e.toString());
          } else {
            await store.updateStatus(op.opId, SyncStatus.pending,
                attempts: attempts,
                lastError: e.toString(),
                nextRetryAt: _backoff(attempts));
          }
        }
      }
      try {
        await _pullMines();
      } catch (_) {
        // Réseau indisponible : le référentiel local reste, on réessaiera.
      }
    } finally {
      _running = false;
    }
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

  /// Backoff exponentiel : 1, 2, 4, 8… minutes, plafonné à 6 h.
  DateTime _backoff(int attempts) {
    final minutes = (1 << (attempts - 1)).clamp(1, 360); // 2^(n-1), max 360 min
    return DateTime.now().add(Duration(minutes: minutes));
  }
}
