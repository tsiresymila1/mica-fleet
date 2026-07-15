import 'dart:io';
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
        await _uploadPendingPhotos();
      } catch (_) {
        // Réseau indisponible : réessai au prochain sync.
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

  /// Après le submit d'un chargement (op synced), envoie ses photos en un batch,
  /// puis marque et purge les fichiers locaux. Réessayé tant que non uploadé.
  Future<void> _uploadPendingPhotos() async {
    final syncedOps = await (db.select(db.syncQueue)
          ..where((t) =>
              t.status.equals('synced') & t.entityType.equals('chargement')))
        .get();
    for (final op in syncedOps) {
      final charg = await (db.select(db.chargements)
            ..where((t) => t.id.equals(op.entityId)))
          .getSingleOrNull();
      if (charg == null || charg.photosUploaded) continue;
      final photos = await _collectPhotos(charg.id);
      await remote.uploadPhotos(charg.deviceUuid ?? charg.id, photos);
      // Succès : marque uploadé + purge les fichiers (le hash reste comme preuve).
      await (db.update(db.chargements)..where((t) => t.id.equals(charg.id)))
          .write(const ChargementsCompanion(photosUploaded: Value(true)));
      for (final p in photos) {
        try {
          await File(p.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<List<PhotoPart>> _collectPhotos(String chargementId) async {
    final parts = <PhotoPart>[];
    final mines = await (db.select(db.mineChargements)
          ..where((t) => t.chargementId.equals(chargementId)))
        .get();
    for (final m in mines) {
      if (m.photoPath != null) {
        parts.add(PhotoPart('mine_${m.mineId}', m.photoPath!, m.photoHash));
      }
    }
    final trans = await (db.select(db.transbordements)
          ..where((t) => t.chargementId.equals(chargementId)))
        .get();
    for (final t in trans) {
      if (t.photoDechargePath != null) {
        parts.add(
            PhotoPart('transb_${t.ordre}_decharge', t.photoDechargePath!, null));
      }
      if (t.photoRechargePath != null) {
        parts.add(
            PhotoPart('transb_${t.ordre}_recharge', t.photoRechargePath!, null));
      }
    }
    final arr = await (db.select(db.arriveesDepot)
          ..where((t) => t.chargementId.equals(chargementId)))
        .getSingleOrNull();
    if (arr != null) {
      if (arr.photoArriveePath != null) {
        parts.add(PhotoPart('arrivee', arr.photoArriveePath!, null));
      }
      if (arr.photoPermisPath != null) {
        parts.add(PhotoPart('permis', arr.photoPermisPath!, null));
      }
    }
    return parts.where((p) => File(p.path).existsSync()).toList();
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
