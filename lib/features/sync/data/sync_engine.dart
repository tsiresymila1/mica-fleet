import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/network/api_error_details.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';
import '../domain/repositories/remote_data_source.dart';

class SyncEngine {
  final LocalSyncStore store;
  final RemoteDataSource remote;
  final AppDatabase db;
  final _uuid = const Uuid();
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
          final operation = await _normalizePendingLotIdentifiers(op);
          final odooId = await remote.pushOperation(operation);
          await store.updateStatus(
            op.opId,
            SyncStatus.synced,
            odooId: odooId,
            syncedAt: DateTime.now(),
          );
          if (op.entityType == 'mine_submission') {
            await (db.update(
              db.mineSubmissions,
            )..where((t) => t.payloadId.equals(op.entityId))).write(
              MineSubmissionsCompanion(
                state: const Value('awaiting_attachments'),
                serverId: Value(odooId),
                updatedAt: Value(DateTime.now()),
              ),
            );
          }
        } catch (e) {
          final attempts = op.attempts + 1;
          if (attempts >= maxAttempts) {
            // Échec terminal après N tentatives → intervention manuelle.
            await store.updateStatus(
              op.opId,
              SyncStatus.failed,
              attempts: attempts,
              lastError: apiErrorDetails(e),
            );
          } else {
            await store.updateStatus(
              op.opId,
              SyncStatus.pending,
              attempts: attempts,
              lastError: apiErrorDetails(e),
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
        await _uploadPendingMinePhotos();
      } catch (_) {
        // Les preuves restantes seront reprises au prochain passage.
      }
      try {
        await _pollMineSubmissionStatuses();
      } catch (_) {
        // Le statut de validation sera relu au prochain passage.
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

  /// Met à niveau une opération qui aurait été créée sans UUID API. Une op
  /// encore pending n'a pas été confirmée par Odoo : on peut donc lui affecter
  /// les UUID persistés du lot et de sa session.
  /// Les opérations déjà synced ne passent pas ici, afin que leurs photos
  /// continuent de cibler l'identifiant réellement soumis au serveur.
  Future<SyncOperation> _normalizePendingLotIdentifiers(
    SyncOperation op,
  ) async {
    if (op.entityType != 'lot') return op;
    final lot = await (db.select(
      db.lots,
    )..where((t) => t.id.equals(op.entityId))).getSingleOrNull();
    if (lot == null) return op;

    final session = await (db.select(
      db.chargements,
    )..where((t) => t.id.equals(lot.sessionId))).getSingleOrNull();
    if (session == null) return op;

    final currentPayloadId = op.payload['id']?.toString();
    final currentSessionId = op.payload['session_id']?.toString();
    final payloadId =
        currentPayloadId != null &&
            Uuid.isValidUUID(fromString: currentPayloadId)
        ? currentPayloadId
        : (lot.payloadUuid ?? _uuid.v4());
    final sessionId =
        currentSessionId != null &&
            Uuid.isValidUUID(fromString: currentSessionId)
        ? currentSessionId
        : (session.sessionUuid ?? _uuid.v4());

    if (lot.payloadUuid != payloadId || session.sessionUuid != sessionId) {
      await db.transaction(() async {
        if (lot.payloadUuid != payloadId) {
          await (db.update(db.lots)..where((t) => t.id.equals(lot.id))).write(
            LotsCompanion(payloadUuid: Value(payloadId)),
          );
        }
        if (session.sessionUuid != sessionId) {
          await (db.update(db.chargements)
                ..where((t) => t.id.equals(session.id)))
              .write(ChargementsCompanion(sessionUuid: Value(sessionId)));
        }
      });
    }

    if (currentPayloadId == payloadId && currentSessionId == sessionId) {
      return op;
    }

    final payload = Map<String, dynamic>.from(op.payload)
      ..['id'] = payloadId
      ..['session_id'] = sessionId;
    await (db.update(db.syncQueue)..where((t) => t.opId.equals(op.opId))).write(
      SyncQueueCompanion(payload: Value(jsonEncode(payload))),
    );
    return op.copyWith(payload: payload);
  }

  /// Après le submit d'un LOT (op synced), envoie chaque photo séparément.
  /// Les fichiers restent sur l'appareil pour être consultables dans le détail
  /// du lot. Les clés confirmées sont persistées séparément afin qu'une reprise
  /// n'envoie que les photos restantes.
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
      final uploadedKeys = _decodeUploadedPhotoKeys(lot.uploadedPhotoKeys);
      final photos = await _collectPhotos(lot.id, excludeKeys: uploadedKeys);
      for (final photo in photos) {
        try {
          await remote.uploadPhoto(lot.deviceUuid ?? op.opId, payloadId, photo);
        } catch (error) {
          await store.updateStatus(
            op.opId,
            SyncStatus.synced,
            lastError:
                'Échec de la photo « ${photo.key} »\n${apiErrorDetails(error)}',
          );
          rethrow;
        }
        uploadedKeys.add(photo.key);
        await (db.update(db.lots)..where((t) => t.id.equals(lot.id))).write(
          LotsCompanion(
            uploadedPhotoKeys: Value(jsonEncode(uploadedKeys.toList())),
          ),
        );
      }
      // Toutes les photos présentes ont été confirmées par le serveur.
      await (db.update(db.lots)..where((t) => t.id.equals(lot.id))).write(
        const LotsCompanion(photosUploaded: Value(true)),
      );
      await store.updateStatus(op.opId, SyncStatus.synced, lastError: null);
    }
  }

  /// Photos d'UN lot : sa photo de mine, celles de ses transbordements, et
  /// celles de son arrivée. Clés scopées au lot (1 submit = 1 lot).
  Future<List<PhotoPart>> _collectPhotos(
    String lotId, {
    Set<String> excludeKeys = const {},
  }) async {
    final parts = <PhotoPart>[];
    Future<void> add(String key, String? path, String? storedHash) async {
      if (path == null || excludeKeys.contains(key)) return;
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

  Set<String> _decodeUploadedPhotoKeys(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // Une ancienne valeur invalide ne doit pas empêcher la reprise.
    }
    return <String>{};
  }

  /// Après le submit d'une proposition, envoie ses preuves une par une. Le
  /// booléen `uploaded` garantit qu'un échec partiel ne rejoue que le reliquat.
  Future<void> _uploadPendingMinePhotos() async {
    final submissions =
        await (db.select(db.mineSubmissions)..where(
              (t) =>
                  t.state.equals('awaiting_attachments') |
                  t.state.equals('pending_validation'),
            ))
            .get();
    for (final submission in submissions) {
      final op =
          await (db.select(db.syncQueue)..where(
                (t) =>
                    t.entityType.equals('mine_submission') &
                    t.entityId.equals(submission.payloadId) &
                    t.status.equals('synced'),
              ))
              .getSingleOrNull();
      if (op == null) continue;

      final pending =
          await (db.select(db.mineSubmissionPhotos)
                ..where(
                  (t) =>
                      t.payloadId.equals(submission.payloadId) &
                      t.uploaded.equals(false),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
              .get();
      var uploadFailed = false;
      for (final photo in pending) {
        try {
          await remote.uploadMinePhoto(
            submission.deviceUuid,
            submission.payloadId,
            PhotoPart(photo.key, photo.path, photo.hash),
          );
          await (db.update(db.mineSubmissionPhotos)..where(
                (t) =>
                    t.payloadId.equals(submission.payloadId) &
                    t.key.equals(photo.key),
              ))
              .write(
                const MineSubmissionPhotosCompanion(uploaded: Value(true)),
              );
          try {
            await File(photo.path).delete();
          } catch (_) {
            // L'upload confirmé ne doit jamais être rejoué pour un souci local.
          }
        } catch (error) {
          await store.updateStatus(
            op.opId,
            SyncStatus.synced,
            lastError:
                'Échec de la photo mine « ${photo.key} »\n${apiErrorDetails(error)}',
          );
          uploadFailed = true;
          break;
        }
      }
      if (uploadFailed) continue;

      final remaining =
          await (db.select(db.mineSubmissionPhotos)..where(
                (t) =>
                    t.payloadId.equals(submission.payloadId) &
                    t.uploaded.equals(false),
              ))
              .get();
      if (remaining.isEmpty) {
        await (db.update(
          db.mineSubmissions,
        )..where((t) => t.payloadId.equals(submission.payloadId))).write(
          MineSubmissionsCompanion(
            state: const Value('pending_validation'),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await store.updateStatus(op.opId, SyncStatus.synced, lastError: null);
      }
    }
  }

  /// Récupère la décision Odoo. Seule une réponse `approved` contenant une mine
  /// canonique alimente le référentiel sélectionnable par les chargements.
  Future<void> _pollMineSubmissionStatuses() async {
    final submissions = await (db.select(
      db.mineSubmissions,
    )..where((t) => t.state.equals('pending_validation'))).get();
    for (final submission in submissions) {
      try {
        final status = await remote.fetchMineSubmissionStatus(
          submission.payloadId,
        );
        if (status.state == 'approved' && status.mine == null) {
          throw const FormatException(
            'Une proposition approuvée doit contenir la mine validée',
          );
        }
        await db.transaction(() async {
          final mine = status.mine;
          if (status.state == 'approved' && mine != null) {
            await db
                .into(db.mines)
                .insert(
                  MinesCompanion.insert(
                    id: mine.id,
                    nom: mine.nom,
                    lat: mine.lat,
                    lon: mine.lon,
                    rayonMetres: Value(mine.rayonMetres),
                    district: Value(mine.district),
                    commune: Value(mine.commune),
                    region: Value(mine.region),
                    actif: Value(mine.actif),
                  ),
                  mode: InsertMode.insertOrReplace,
                );
          }
          await (db.update(
            db.mineSubmissions,
          )..where((t) => t.payloadId.equals(submission.payloadId))).write(
            MineSubmissionsCompanion(
              state: Value(status.state),
              approvedMineId: Value(mine?.id),
              rejectionReason: Value(status.rejectionReason),
              updatedAt: Value(DateTime.now()),
            ),
          );
        });
        await store.updateStatus(
          submission.deviceUuid,
          SyncStatus.synced,
          lastError: null,
        );
      } catch (error) {
        await store.updateStatus(
          submission.deviceUuid,
          SyncStatus.synced,
          lastError: 'Validation de la mine\n${apiErrorDetails(error)}',
        );
      }
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
