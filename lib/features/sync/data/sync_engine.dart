import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
        // Réservation atomique : si un autre process (sync en arrière-plan) l'a
        // déjà prise, on saute — pas de double envoi.
        if (!await store.claim(op.opId)) continue;
        try {
          final odooId = await remote.pushOperation(op);
          await store.updateStatus(
            op.opId,
            SyncStatus.synced,
            odooId: odooId,
            syncedAt: DateTime.now(),
          );
        } catch (e) {
          final attempts = op.attempts + 1;
          if (attempts >= maxAttempts) {
            // Échec terminal après N tentatives → intervention manuelle.
            await store.updateStatus(
              op.opId,
              SyncStatus.failed,
              attempts: attempts,
              lastError: e.toString(),
            );
          } else {
            await store.updateStatus(
              op.opId,
              SyncStatus.pending,
              attempts: attempts,
              lastError: e.toString(),
              nextRetryAt: _backoff(attempts),
            );
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

  /// Après le submit d'un LOT (op synced), envoie chaque photo séparément.
  /// Chaque fichier confirmé est purgé immédiatement : en cas d'échec partiel,
  /// le prochain passage ne reprend que les fichiers restants.
  Future<void> _uploadPendingPhotos() async {
    final syncedOps =
        await (db.select(db.syncQueue)..where(
              (t) => t.status.equals('synced') & t.entityType.equals('lot'),
            ))
            .get();
    for (final op in syncedOps) {
      final lot = await (db.select(
        db.lots,
      )..where((t) => t.id.equals(op.entityId))).getSingleOrNull();
      if (lot == null || lot.photosUploaded) continue;
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final payloadId = payload['id']?.toString();
      if (payloadId == null || payloadId.isEmpty) {
        throw StateError('payload.id absent pour le lot ${lot.id}');
      }
      final photos = await _collectPhotos(lot.id);
      for (final photo in photos) {
        await remote.uploadPhoto(lot.deviceUuid ?? op.opId, payloadId, photo);
        try {
          await File(photo.path).delete();
        } catch (_) {
          // L'upload est confirmé. Un fichier impossible à purger ne doit pas
          // provoquer un nouvel envoi ; photosUploaded clôture le lot.
        }
      }
      // Toutes les photos encore présentes ont été confirmées par le serveur.
      await (db.update(db.lots)..where((t) => t.id.equals(lot.id))).write(
        const LotsCompanion(photosUploaded: Value(true)),
      );
    }
  }

  /// Photos d'UN lot : sa photo de mine, celles de ses transbordements, et
  /// celles de son arrivée. Clés scopées au lot (1 submit = 1 lot).
  Future<List<PhotoPart>> _collectPhotos(String lotId) async {
    final parts = <PhotoPart>[];
    Future<void> add(String key, String? path, String? storedHash) async {
      if (path == null) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final hash = storedHash == null || storedHash.isEmpty
          ? (await sha256.bind(file.openRead()).first).toString()
          : storedHash;
      parts.add(PhotoPart(key, path, hash));
    }

    final lot = await (db.select(
      db.lots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    await add('mine', lot?.photoPath, lot?.photoHash);
    final trans = await (db.select(
      db.transbordements,
    )..where((t) => t.lotId.equals(lotId))).get();
    for (final t in trans) {
      await add('transload_${t.ordre}_unload', t.photoDechargePath, null);
      await add('transload_${t.ordre}_reload', t.photoRechargePath, null);
    }
    final arr = await (db.select(
      db.arriveesDepot,
    )..where((t) => t.lotId.equals(lotId))).getSingleOrNull();
    if (arr != null) {
      await add('arrival', arr.photoArriveePath, null);
      await add('license', arr.photoPermisPath, null);
    }
    return parts;
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
