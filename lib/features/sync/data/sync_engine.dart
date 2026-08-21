import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/network/api_error_details.dart';
import '../../auth/data/password_secret_store.dart';
import '../domain/entities/sync_operation.dart';
import '../domain/repositories/local_sync_store.dart';
import '../domain/repositories/remote_data_source.dart';

class MineSubmissionSendResult {
  final bool success;
  final String? error;

  const MineSubmissionSendResult._({required this.success, this.error});

  const MineSubmissionSendResult.sent() : this._(success: true);

  const MineSubmissionSendResult.failed(String message)
    : this._(success: false, error: message);
}

class SyncEngine {
  final LocalSyncStore store;
  final RemoteDataSource remote;
  final AppDatabase db;
  final PasswordSecretStore? passwordStore;
  final _uuid = const Uuid();
  SyncEngine(this.store, this.remote, this.db, [this.passwordStore]);

  static const int maxAttempts = 5; // au-delà → statut failed (terminal)

  Future<void>? _activeSync;

  /// Push FIFO des pending (backoff respecté) puis pull du référentiel.
  /// Ne lève jamais : les erreurs réseau laissent les opérations en attente.
  /// Réentrance protégée (déclenché à la fois par le réseau et le bouton).
  Future<void> sync() {
    final active = _activeSync;
    if (active != null) return active;
    late final Future<void> task;
    task = _syncOnce().whenComplete(() {
      if (identical(_activeSync, task)) _activeSync = null;
    });
    _activeSync = task;
    return task;
  }

  Future<void> _syncOnce() async {
    await _syncPendingPassword();
    final agentLogin = await _activeSupplierId();
    final ops = await store.pending(agentLogin: agentLogin); // batch max 10
    for (final op in ops) {
      await _pushPendingOperation(op);
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
      await _pullMines();
    } catch (_) {
      // Réseau indisponible : le référentiel local reste, on réessaiera.
    }
    try {
      await _pullDepots();
    } catch (_) {
      // Chaque référentiel est indépendant : un endpoint en panne ne bloque
      // pas les deux autres ni le cache déjà disponible.
    }
    try {
      await _pullCommunes();
    } catch (_) {
      // En cas d'indisponibilité, le cache local reste inchangé.
    }
    try {
      await _pullLots();
    } catch (_) {
      // Le cache local reste disponible si l'historique distant est en panne.
    }
  }

  Future<void> _syncPendingPassword() async {
    final secrets = passwordStore;
    if (secrets == null) return;
    final PendingPasswordChange? pending;
    try {
      pending = await secrets.pending();
    } catch (_) {
      // Certains environnements (tests, ancien appareil) n'exposent pas
      // encore le stockage sécurisé. Cela ne doit pas bloquer le reste.
      return;
    }
    if (pending == null) return;
    try {
      await remote.changePassword(
        currentPassword: pending.currentPassword,
        newPassword: pending.newPassword,
      );
      await secrets.clearPending();
    } catch (_) {
      // Le secret reste chiffré et sera repris à la prochaine connexion.
    }
  }

  /// Force immédiatement l'envoi d'une proposition précise, même si son
  /// backoff n'est pas échu ou si elle est passée en échec terminal.
  Future<MineSubmissionSendResult> sendMineSubmissionNow(
    String payloadId,
  ) async {
    final active = _activeSync;
    if (active != null) await active;
    final submission = await (db.select(
      db.mineSubmissions,
    )..where((table) => table.payloadId.equals(payloadId))).getSingleOrNull();
    if (submission == null) {
      return const MineSubmissionSendResult.failed(
        'Proposition locale introuvable.',
      );
    }
    final operation =
        await (db.select(db.syncQueue)..where(
              (table) =>
                  table.entityType.equals('mine_submission') &
                  table.entityId.equals(payloadId),
            ))
            .getSingleOrNull();
    if (operation == null) {
      return const MineSubmissionSendResult.failed(
        'Opération d’envoi locale introuvable.',
      );
    }

    if (operation.status != 'synced') {
      await store.updateStatus(
        operation.opId,
        SyncStatus.pending,
        attempts: operation.status == 'failed' ? 0 : null,
        lastError: null,
        nextRetryAt: null,
      );
      final refreshedOperation = await (db.select(
        db.syncQueue,
      )..where((table) => table.opId.equals(operation.opId))).getSingle();
      await _pushPendingOperation(_operationFromRow(refreshedOperation));
    }
    final submittedMine = await (db.select(
      db.mineSubmissions,
    )..where((table) => table.payloadId.equals(payloadId))).getSingleOrNull();
    if (submittedMine?.serverId != null) {
      // L'id Odoo suffit pour libérer les lots. Les photos de la mine suivent
      // leur propre reprise et ne bloquent pas POST /api/tracking/submit.
      await _resumeLotsDependingOnMine(payloadId);
    }
    try {
      await _uploadPendingMinePhotos(payloadId: payloadId);
    } catch (_) {
      // Le détail de la photo en échec est déjà enregistré dans sync_queue.
    }
    try {
      await _pullMines();
    } catch (_) {
      // Le POST et les pièces jointes peuvent réussir même si le GET échoue.
    }

    final updatedSubmission = await (db.select(
      db.mineSubmissions,
    )..where((table) => table.payloadId.equals(payloadId))).getSingleOrNull();
    final updatedOperation = await (db.select(
      db.syncQueue,
    )..where((table) => table.opId.equals(operation.opId))).getSingleOrNull();
    final remainingPhotos =
        await (db.select(db.mineSubmissionPhotos)..where(
              (table) =>
                  table.payloadId.equals(payloadId) &
                  table.uploaded.equals(false),
            ))
            .get();
    final state = updatedSubmission?.state;
    if ((state == 'pending_validation' || state == 'approved') &&
        remainingPhotos.isEmpty) {
      await _resumeLotsDependingOnMine(payloadId);
      return const MineSubmissionSendResult.sent();
    }
    return MineSubmissionSendResult.failed(
      updatedOperation?.lastError ??
          (state == 'awaiting_attachments'
              ? 'La mine a été créée, mais certaines photos restent à envoyer.'
              : 'Envoi impossible. Vérifiez la connexion puis réessayez.'),
    );
  }

  Future<void> _pushPendingOperation(SyncOperation op) async {
    final preparedOperation = await _prepareOperationDependencies(op);
    if (preparedOperation == null) return;

    // Réservation atomique : si un autre process (sync en arrière-plan) l'a
    // déjà prise, on saute — pas de double envoi.
    if (!await store.claim(preparedOperation.opId)) return;
    try {
      final operation = await _normalizePendingLotIdentifiers(
        preparedOperation,
      );
      final odooId = await remote.pushOperation(operation);
      await store.updateStatus(
        preparedOperation.opId,
        SyncStatus.synced,
        odooId: odooId,
        syncedAt: DateTime.now(),
      );
      if (preparedOperation.entityType == 'mine_submission') {
        await (db.update(
          db.mineSubmissions,
        )..where((t) => t.payloadId.equals(preparedOperation.entityId))).write(
          MineSubmissionsCompanion(
            state: const Value('awaiting_attachments'),
            serverId: Value(odooId),
            updatedAt: Value(DateTime.now()),
          ),
        );
        if (odooId != null) {
          // Réveille les lots dès que POST /api/mine fournit son identifiant.
          // L'upload des preuves mine continue ensuite indépendamment.
          await _resumeLotsDependingOnMine(preparedOperation.entityId);
        }
      }
    } catch (error) {
      final attempts = preparedOperation.attempts + 1;
      if (attempts >= maxAttempts) {
        // Échec terminal après N tentatives → intervention manuelle.
        await store.updateStatus(
          preparedOperation.opId,
          SyncStatus.failed,
          attempts: attempts,
          lastError: apiErrorDetails(error),
        );
      } else {
        await store.updateStatus(
          preparedOperation.opId,
          SyncStatus.pending,
          attempts: attempts,
          lastError: apiErrorDetails(error),
          nextRetryAt: _backoff(attempts),
        );
      }
    }
  }

  /// Un lot créé avec une proposition locale ne peut partir qu'après la
  /// création de cette mine. Le lot conserve l'UUID local comme relation
  /// stable ; seul son payload de sync reçoit l'id Odoo renvoyé par
  /// POST /api/mine. Les photos de la mine ne font pas partie de cette
  /// dépendance et conservent leur propre reprise.
  Future<SyncOperation?> _prepareOperationDependencies(SyncOperation op) async {
    if (op.entityType != 'lot') return op;

    final lot = await (db.select(
      db.lots,
    )..where((table) => table.id.equals(op.entityId))).getSingleOrNull();
    if (lot == null) return op;

    var submission = await (db.select(
      db.mineSubmissions,
    )..where((table) => table.payloadId.equals(lot.mineId))).getSingleOrNull();
    // Mine issue du référentiel : aucune dépendance locale.
    if (submission == null) return op;

    if (submission.state == 'rejected') {
      await store.updateStatus(
        op.opId,
        SyncStatus.failed,
        lastError:
            'Lot bloqué : la mine « ${submission.nom} » a été rejetée.'
            '${submission.rejectionReason == null ? '' : '\n${submission.rejectionReason}'}',
      );
      return null;
    }

    var mineOperation =
        await (db.select(db.syncQueue)..where(
              (table) =>
                  table.entityType.equals('mine_submission') &
                  table.entityId.equals(submission!.payloadId),
            ))
            .getSingleOrNull();
    if (mineOperation == null) {
      await _keepLotWaitingForMine(
        op,
        'Lot en attente : opération locale de la mine introuvable.',
      );
      return null;
    }

    // Répare le cas d'un arrêt entre la confirmation de la queue et la mise
    // à jour de mine_submissions.
    if (submission.serverId == null &&
        mineOperation.status == 'synced' &&
        mineOperation.odooId != null) {
      await (db.update(
        db.mineSubmissions,
      )..where((table) => table.payloadId.equals(submission!.payloadId))).write(
        MineSubmissionsCompanion(
          state: const Value('awaiting_attachments'),
          serverId: Value(mineOperation.odooId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      submission =
          await (db.select(db.mineSubmissions)..where(
                (table) => table.payloadId.equals(submission!.payloadId),
              ))
              .getSingle();
    }

    if (submission.serverId == null && mineOperation.status == 'pending') {
      final retryAt = mineOperation.nextRetryAt;
      if (retryAt == null || !retryAt.isAfter(DateTime.now())) {
        await _pushPendingOperation(_operationFromRow(mineOperation));
        submission =
            await (db.select(db.mineSubmissions)..where(
                  (table) => table.payloadId.equals(submission!.payloadId),
                ))
                .getSingle();
        mineOperation =
            await (db.select(db.syncQueue)
                  ..where((table) => table.opId.equals(mineOperation!.opId)))
                .getSingle();
      }
    }

    if (submission.serverId == null) {
      final detail = mineOperation.lastError?.trim();
      await _keepLotWaitingForMine(
        op,
        'Lot en attente de synchronisation de la mine « ${submission.nom} ».'
        '${detail == null || detail.isEmpty ? '' : '\n$detail'}',
      );
      return null;
    }

    final payload = Map<String, dynamic>.from(op.payload);
    final rawMine = payload['mine'];
    if (rawMine is! Map) {
      await _keepLotWaitingForMine(
        op,
        'Lot bloqué : la section payload.mine est absente.',
      );
      return null;
    }
    final minePayload = Map<String, dynamic>.from(
      rawMine.cast<String, dynamic>(),
    )..['mine_id'] = submission.serverId;
    payload['mine'] = minePayload;

    if (jsonEncode(payload) != jsonEncode(op.payload)) {
      await (db.update(
        db.syncQueue,
      )..where((table) => table.opId.equals(op.opId))).write(
        SyncQueueCompanion(
          payload: Value(jsonEncode(payload)),
          lastError: const Value(null),
          nextRetryAt: const Value(null),
        ),
      );
    }
    return op.copyWith(payload: payload, lastError: null, nextRetryAt: null);
  }

  Future<void> _keepLotWaitingForMine(
    SyncOperation lotOperation,
    String message,
  ) => store.updateStatus(
    lotOperation.opId,
    SyncStatus.pending,
    lastError: message,
    nextRetryAt: lotOperation.nextRetryAt,
  );

  /// L'envoi manuel d'une mine doit réveiller immédiatement les lots qui
  /// l'attendaient, sans attendre le prochain cycle réseau.
  Future<void> _resumeLotsDependingOnMine(String payloadId) async {
    final lots = await (db.select(
      db.lots,
    )..where((table) => table.mineId.equals(payloadId))).get();
    if (lots.isEmpty) return;

    final now = DateTime.now();
    for (final lot in lots) {
      final operation =
          await (db.select(db.syncQueue)..where(
                (table) =>
                    table.entityType.equals('lot') &
                    table.entityId.equals(lot.id) &
                    table.status.equals('pending'),
              ))
              .getSingleOrNull();
      if (operation == null) continue;
      final retryAt = operation.nextRetryAt;
      if (retryAt != null && retryAt.isAfter(now)) continue;
      await _pushPendingOperation(_operationFromRow(operation));
    }
    try {
      await _uploadPendingPhotos();
    } catch (_) {
      // Les photos de lot restantes gardent leur reprise idempotente normale.
    }
  }

  SyncOperation _operationFromRow(SyncQueueRow row) => SyncOperation(
    opId: row.opId,
    entityType: row.entityType,
    entityId: row.entityId,
    opType: SyncOpType.values.byName(row.opType),
    payload: jsonDecode(row.payload) as Map<String, dynamic>,
    status: SyncStatus.values.byName(row.status),
    attempts: row.attempts,
    lastError: row.lastError,
    createdAt: row.createdAt,
    nextRetryAt: row.nextRetryAt,
    odooId: row.odooId,
    syncedAt: row.syncedAt,
    agentLogin: row.agentLogin,
    gpsLat: row.gpsLat,
    gpsLon: row.gpsLon,
    gpsAccuracy: row.gpsAccuracy,
  );

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
    if ((lot?.photoSchemaVersion ?? 1) >= 2) {
      final rows =
          await (db.select(db.lotTraceabilityPhotos)
                ..where((table) => table.lotId.equals(lotId))
                ..orderBy([
                  (table) => OrderingTerm.asc(table.stageOrder),
                  (table) => OrderingTerm.asc(table.role),
                ]))
              .get();
      for (final row in rows) {
        final prefix = switch (row.stage) {
          'mine' => 'mine',
          'transload_unload' => 'transload_${row.stageOrder}_unload',
          'transload_reload' => 'transload_${row.stageOrder}_reload',
          'depot_unload' => 'depot_unload',
          _ => row.stage,
        };
        await add('${prefix}_${row.role}', row.path, row.hash);
      }
    } else {
      await add('mine', lot?.photoPath, lot?.photoHash);
    }
    final trans = await (db.select(
      db.transbordements,
    )..where((t) => t.lotId.equals(lotId))).get();
    if ((lot?.photoSchemaVersion ?? 1) < 2) {
      for (final t in trans) {
        await add('transload_${t.ordre}_unload', t.photoDechargePath, null);
        await add('transload_${t.ordre}_reload', t.photoRechargePath, null);
      }
    }
    final arr = await (db.select(
      db.arriveesDepot,
    )..where((t) => t.lotId.equals(lotId))).getSingleOrNull();
    if (arr != null) {
      if ((lot?.photoSchemaVersion ?? 1) < 2) {
        await add('arrival', arr.photoArriveePath, null);
      }
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
  Future<void> _uploadPendingMinePhotos({String? payloadId}) async {
    final query = db.select(db.mineSubmissions)
      ..where(
        (table) =>
            table.state.equals('awaiting_attachments') |
            table.state.equals('pending_validation'),
      );
    if (payloadId != null) {
      query.where((table) => table.payloadId.equals(payloadId));
    }
    final submissions = await query.get();
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

  Future<void> _pullMines() async {
    final mines = await remote.fetchMines();
    await db.transaction(() async {
      await db
          .update(db.mines)
          .write(const MinesCompanion(actif: Value(false)));
      await db.batch((batch) {
        for (final mine in mines) {
          batch.insert(
            db.mines,
            MinesCompanion.insert(
              id: mine.id,
              nom: mine.nom,
              lat: mine.lat,
              lon: mine.lon,
              rayonMetres: Value(mine.rayonMetres),
              reference: Value(mine.reference),
              note: Value(mine.note),
              createdAt: Value(mine.createdAt),
              district: Value(mine.district),
              fokontany: Value(mine.fokontany),
              commune: Value(mine.commune),
              region: Value(mine.region),
              actif: Value(mine.actif),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });

      // POST /api/mine renvoie l'id serveur de la proposition. GET /api/mine
      // ne contient que les mines validées : le même id qui réapparaît est
      // donc la confirmation de validation, sans endpoint de statut dédié.
      final submissions =
          await (db.select(db.mineSubmissions)..where(
                (table) =>
                    table.serverId.isNotNull() &
                    table.state.equals('approved').not(),
              ))
              .get();
      final minesById = {for (final mine in mines) mine.id: mine};
      for (final submission in submissions) {
        final mine = minesById[submission.serverId.toString()];
        if (mine == null) continue;
        await (db.update(db.mineSubmissions)
              ..where((table) => table.payloadId.equals(submission.payloadId)))
            .write(
              MineSubmissionsCompanion(
                state: const Value('approved'),
                approvedMineId: Value(mine.id),
                rejectionReason: const Value(null),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }
    });
  }

  Future<void> _pullDepots() async {
    final depots = await remote.fetchDepots();
    await db.transaction(() async {
      await db
          .update(db.depots)
          .write(const DepotsCompanion(actif: Value(false)));
      await db.batch((batch) {
        for (final depot in depots) {
          batch.insert(
            db.depots,
            DepotsCompanion.insert(
              id: depot.id,
              nom: depot.nom,
              lat: depot.lat,
              lon: depot.lon,
              rayonMetres: Value(depot.rayonMetres),
              actif: Value(depot.actif),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  Future<void> _pullCommunes() async {
    final communes = await remote.fetchCommunes();
    await db.transaction(() async {
      await db
          .update(db.communes)
          .write(const CommunesCompanion(actif: Value(false)));
      await db.batch((batch) {
        for (final commune in communes) {
          batch.insert(
            db.communes,
            CommunesCompanion.insert(
              id: Value(commune.id),
              nom: commune.name,
              district: Value(commune.district),
              actif: Value(commune.actif),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  Future<void> _pullLots() async {
    final currentSupplierId = await _activeSupplierId();
    if (currentSupplierId == null) {
      // Sans session active, ne touche pas au cache lot (évite mélange).
      return;
    }

    final remoteLots = await remote.fetchLots();
    final remotePayloadIds = <String>{};
    for (final remoteLot in remoteLots) {
      remotePayloadIds.add(remoteLot.payloadId);
      await _mergeMineMetadataFromRemoteLot(remoteLot);
      // `remoteLot.payloadId` correspond à payload.id dans le submit. C'est
      // la clé de fusion stable entre appareils et évite tout doublon local.
      final local =
          await (db.select(db.lots)..where(
                (table) => table.payloadUuid.equals(remoteLot.payloadId),
              ))
              .getSingleOrNull();
      if (local != null) {
        await (db.update(
          db.lots,
        )..where((table) => table.id.equals(local.id))).write(
          LotsCompanion(
            mineId: Value(remoteLot.mineId),
            serverReference: Value(remoteLot.reference),
            validationStatus: Value(remoteLot.validationStatus),
            validationReason: Value(remoteLot.validationReason),
            serverUpdatedAt: Value(remoteLot.updatedAt ?? DateTime.now()),
            // Après un GET tracking, le score serveur est la seule valeur
            // canonique. Un null serveur efface donc le score provisoire local.
            score: Value(remoteLot.score),
          ),
        );
        continue;
      }

      await db.transaction(() async {
        final cachedSessionId =
            'REMOTE-$currentSupplierId-${remoteLot.sessionId}';
        await db
            .into(db.chargements)
            .insert(
              ChargementsCompanion.insert(
                id: cachedSessionId,
                sessionUuid: Value(remoteLot.sessionId),
                fournisseurId: currentSupplierId,
                dateCreation: remoteLot.createdAt,
                statut: const Value('synchronise'),
              ),
              mode: InsertMode.insertOrIgnore,
            );

        await db
            .into(db.lots)
            .insert(
              LotsCompanion.insert(
                id: 'REMOTE-${remoteLot.payloadId}',
                payloadUuid: Value(remoteLot.payloadId),
                sessionId: cachedSessionId,
                mineId: remoteLot.mineId,
                couleur: Value(remoteLot.color),
                quantiteEstimee: Value(remoteLot.estimatedQuantity),
                statut: Value(remoteLot.transportStatus),
                score: Value(remoteLot.score),
                photosUploaded: const Value(true),
                photoSchemaVersion: const Value(3),
                validationStatus: Value(remoteLot.validationStatus),
                validationReason: Value(remoteLot.validationReason),
                serverReference: Value(remoteLot.reference),
                serverUpdatedAt: Value(remoteLot.updatedAt),
                remoteOnly: const Value(true),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      });
    }

    await _deleteLotsMissingOnServer(currentSupplierId, remotePayloadIds);
  }

  /// `GET /api/tracking/lots` est la source de la note affichée pour une
  /// mine. La fusion s'applique aussi si GET /api/mine a déjà créé la ligne.
  Future<void> _mergeMineMetadataFromRemoteLot(RemoteLot remoteLot) async {
    final mine = await (db.select(
      db.mines,
    )..where((table) => table.id.equals(remoteLot.mineId))).getSingleOrNull();
    if (mine == null) {
      await db
          .into(db.mines)
          .insert(
            MinesCompanion.insert(
              id: remoteLot.mineId,
              nom: remoteLot.mineName,
              reference: Value(remoteLot.mineReference),
              note: Value(remoteLot.mineNote),
              createdAt: Value(remoteLot.createdAt),
              lat: 0,
              lon: 0,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      return;
    }

    await (db.update(
      db.mines,
    )..where((table) => table.id.equals(remoteLot.mineId))).write(
      MinesCompanion(
        nom: remoteLot.mineName == remoteLot.mineId
            ? const Value.absent()
            : Value(remoteLot.mineName),
        reference: remoteLot.mineReference == null
            ? const Value.absent()
            : Value(remoteLot.mineReference),
        // La valeur de tracking est autoritaire, y compris null.
        note: Value(remoteLot.mineNote),
      ),
    );
  }

  Future<void> _deleteLotsMissingOnServer(
    String supplierId,
    Set<String> remotePayloadIds,
  ) async {
    final supplierSessions = await (db.select(
      db.chargements,
    )..where((t) => t.fournisseurId.equals(supplierId))).get();
    if (supplierSessions.isEmpty) return;
    final sessionIds = supplierSessions.map((s) => s.id).toSet();
    final supplierLots = await (db.select(
      db.lots,
    )..where((t) => t.sessionId.isIn(sessionIds))).get();

    for (final lot in supplierLots) {
      if (lot.payloadUuid == null) continue;
      if (!lot.remoteOnly) {
        final hasLotSyncOp =
            await (db.select(db.syncQueue)..where(
                  (t) => t.entityType.equals('lot') & t.entityId.equals(lot.id),
                ))
                .getSingleOrNull();
        if (hasLotSyncOp == null) continue;
      }
      if (remotePayloadIds.contains(lot.payloadUuid!)) continue;
      if (await _lotHasPendingSyncQueue(lot.id)) continue;
      await _deleteRemoteOnlyLotCascade(lot.id);
    }

    for (final session in supplierSessions) {
      final hasLots =
          await (db.select(db.lots)
                ..where((t) => t.sessionId.equals(session.id)))
              .get()
              .then((rows) => rows.isNotEmpty);
      if (!hasLots) {
        await (db.delete(
          db.chargements,
        )..where((t) => t.id.equals(session.id))).go();
      }
    }
  }

  Future<bool> _lotHasPendingSyncQueue(String lotId) async {
    final blocking =
        await (db.select(db.syncQueue)..where(
              (t) =>
                  t.entityType.equals('lot') &
                  t.entityId.equals(lotId) &
                  t.status.equals('synced').not(),
            ))
            .getSingleOrNull();
    return blocking != null;
  }

  Future<void> _deleteRemoteOnlyLotCascade(String lotId) async {
    await db.transaction(() async {
      await (db.delete(
        db.lotTraceabilityPhotos,
      )..where((t) => t.lotId.equals(lotId))).go();
      await (db.delete(
        db.transbordements,
      )..where((t) => t.lotId.equals(lotId))).go();
      await (db.delete(
        db.arriveesDepot,
      )..where((t) => t.lotId.equals(lotId))).go();
      await (db.delete(
        db.syncQueue,
      )..where((t) => t.entityId.equals(lotId))).go();
      await (db.delete(db.lots)..where((t) => t.id.equals(lotId))).go();
    });
  }

  Future<String?> _activeSupplierId() async {
    final sessions = await (db.select(
      db.fournisseurs,
    )..where((t) => t.sessionToken.isNotNull())).get();
    return sessions.firstOrNull?.id;
  }

  /// Backoff exponentiel : 1, 2, 4, 8… minutes, plafonné à 6 h.
  DateTime _backoff(int attempts) {
    final minutes = (1 << (attempts - 1)).clamp(1, 360); // 2^(n-1), max 360 min
    return DateTime.now().add(Duration(minutes: minutes));
  }
}
