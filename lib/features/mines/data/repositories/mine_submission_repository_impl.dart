import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../capture/domain/entities/captured_photo.dart';
import '../../domain/entities/mine_submission.dart';
import '../../domain/repositories/mine_submission_repository.dart';

class MineSubmissionRepositoryImpl implements MineSubmissionRepository {
  static const minPhotos = 5;

  final AppDatabase db;
  final Future<Directory> Function()? storageDirectory;
  final _uuid = const Uuid();

  MineSubmissionRepositoryImpl(this.db, {this.storageDirectory});

  @override
  Future<Either<Failure, MineSubmission>> create({
    required String name,
    required List<CapturedPhoto> photos,
    String? agentLogin,
    int? communeId,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      return left(
        const Failure.validation('Le nom de la mine est obligatoire'),
      );
    }
    if (photos.length < minPhotos) {
      return left(
        const Failure.validation(
          'Au moins 5 photos géolocalisées sont obligatoires',
        ),
      );
    }
    final payloadId = _uuid.v4();
    final deviceUuid = _uuid.v4();
    final now = DateTime.now();
    Directory? submissionDirectory;
    try {
      final baseDirectory = storageDirectory == null
          ? await getApplicationDocumentsDirectory()
          : await storageDirectory!();
      submissionDirectory = Directory(
        p.join(baseDirectory.path, 'mine_submissions', payloadId),
      );
      await submissionDirectory.create(recursive: true);
      final parts = <MineSubmissionPhoto>[];
      for (var i = 0; i < photos.length; i++) {
        final key = 'position_${i + 1}';
        final source = File(photos[i].path);
        if (!await source.exists()) {
          throw FileSystemException('Photo locale introuvable', source.path);
        }
        final stored = await source.copy(
          p.join(submissionDirectory.path, '$key.jpg'),
        );
        final storedHash = (await sha256.bind(stored.openRead()).first)
            .toString();
        final original = photos[i];
        parts.add(
          MineSubmissionPhoto(
            key: key,
            photo: CapturedPhoto(
              path: stored.path,
              sha256: storedHash,
              lat: original.lat,
              lon: original.lon,
              precision: original.precision,
              takenAt: original.takenAt,
              headingDegrees: original.headingDegrees,
              headingAccuracy: original.headingAccuracy,
              headingReference: original.headingReference,
            ),
          ),
        );
      }
      final payload = <String, dynamic>{
        'id': payloadId,
        'name': normalizedName,
        'created_at': _odooDate(now),
        ...communeId == null ? {} : {'commune_id': communeId},
        'positions': [
          for (final part in parts)
            {
              'key': part.key,
              'hash': part.photo.sha256,
              'lat': part.photo.lat,
              'lon': part.photo.lon,
              'gps_accuracy': part.photo.precision,
              'captured_at': _odooDate(part.photo.takenAt),
              if (part.photo.headingDegrees != null)
                'heading_deg': part.photo.headingDegrees,
              if (part.photo.headingAccuracy != null)
                'heading_accuracy': part.photo.headingAccuracy,
              if (part.photo.headingReference != null)
                'heading_reference': part.photo.headingReference,
            },
        ],
      };
      await db.transaction(() async {
        // Le lot peut référencer cette proposition avant sa synchronisation.
        // Une ligne inactive satisfait la relation locale Lots.mineId sans
        // faire apparaître la proposition dans le référentiel validé.
        final firstPosition = parts.first.photo;
        await db
            .into(db.mines)
            .insert(
              MinesCompanion.insert(
                id: payloadId,
                nom: normalizedName,
                lat: firstPosition.lat,
                lon: firstPosition.lon,
                createdAt: Value(now),
                actif: const Value(false),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        await db
            .into(db.mineSubmissions)
            .insert(
              MineSubmissionsCompanion.insert(
                payloadId: payloadId,
                deviceUuid: deviceUuid,
                nom: normalizedName,
                communeId: Value(communeId),
                agentLogin: Value(agentLogin),
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final part in parts) {
          await db
              .into(db.mineSubmissionPhotos)
              .insert(
                MineSubmissionPhotosCompanion.insert(
                  payloadId: payloadId,
                  key: part.key,
                  path: part.photo.path,
                  hash: part.photo.sha256,
                  lat: part.photo.lat,
                  lon: part.photo.lon,
                  gpsAccuracy: part.photo.precision,
                  headingDegrees: Value(part.photo.headingDegrees),
                  headingAccuracy: Value(part.photo.headingAccuracy),
                  headingReference: Value(part.photo.headingReference),
                  capturedAt: part.photo.takenAt,
                ),
              );
        }
        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                opId: deviceUuid,
                entityType: 'mine_submission',
                entityId: payloadId,
                opType: 'create',
                payload: jsonEncode(payload),
                createdAt: now,
                agentLogin: Value(agentLogin),
              ),
            );
      });
      for (final original in photos) {
        try {
          await File(original.path).delete();
        } catch (_) {
          // La copie durable est enregistrée ; un cache impossible à purger
          // ne doit pas annuler la proposition.
        }
      }
      return right(
        MineSubmission(
          payloadId: payloadId,
          deviceUuid: deviceUuid,
          nom: normalizedName,
          agentLogin: agentLogin,
          state: MineSubmissionState.localPending,
          createdAt: now,
          updatedAt: now,
          photos: parts,
        ),
      );
    } catch (error) {
      if (submissionDirectory != null && await submissionDirectory.exists()) {
        await submissionDirectory.delete(recursive: true);
      }
      return left(Failure.database(error.toString()));
    }
  }

  @override
  Future<List<MineSubmission>> list({String? agentLogin}) async {
    final query = db.select(db.mineSubmissions)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (agentLogin != null) {
      query.where((t) => t.agentLogin.equals(agentLogin));
    }
    final rows = await query.get();
    final result = <MineSubmission>[];
    for (final row in rows) {
      final photos =
          await (db.select(db.mineSubmissionPhotos)
                ..where((t) => t.payloadId.equals(row.payloadId))
                ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
              .get();
      result.add(
        MineSubmission(
          payloadId: row.payloadId,
          deviceUuid: row.deviceUuid,
          nom: row.nom,
          communeId: row.communeId,
          agentLogin: row.agentLogin,
          state: MineSubmissionState.fromValue(row.state),
          serverId: row.serverId,
          approvedMineId: row.approvedMineId,
          rejectionReason: row.rejectionReason,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          photos: [
            for (final photo in photos)
              MineSubmissionPhoto(
                key: photo.key,
                uploaded: photo.uploaded,
                photo: CapturedPhoto(
                  path: photo.path,
                  sha256: photo.hash,
                  lat: photo.lat,
                  lon: photo.lon,
                  precision: photo.gpsAccuracy,
                  takenAt: photo.capturedAt,
                  headingDegrees: photo.headingDegrees,
                  headingAccuracy: photo.headingAccuracy,
                  headingReference: photo.headingReference,
                ),
              ),
          ],
        ),
      );
    }
    return result;
  }

  @override
  Future<Either<Failure, Unit>> delete(String payloadId) async {
    try {
      final submission = await (db.select(
        db.mineSubmissions,
      )..where((table) => table.payloadId.equals(payloadId))).getSingleOrNull();
      final dependentLot = await (db.select(
        db.lots,
      )..where((table) => table.mineId.equals(payloadId))).getSingleOrNull();
      if (dependentLot != null) {
        return left(
          const Failure.validation(
            'Cette mine est utilisée par un lot local et ne peut pas être supprimée.',
          ),
        );
      }
      final photos = await (db.select(
        db.mineSubmissionPhotos,
      )..where((table) => table.payloadId.equals(payloadId))).get();
      final keepServerLink =
          submission?.serverId != null && submission?.state != 'rejected';
      await db.transaction(() async {
        await (db.delete(
          db.mineSubmissionPhotos,
        )..where((table) => table.payloadId.equals(payloadId))).go();
        await (db.delete(db.syncQueue)..where(
              (table) =>
                  table.entityType.equals('mine_submission') &
                  table.entityId.equals(payloadId),
            ))
            .go();
        if (keepServerLink) {
          // La ligne devient un tombstone invisible. Elle conserve le lien
          // payload local → id Odoo tant que GET /api/mine ne retourne pas
          // encore la mine validée, y compris après un refetch.
          await (db.update(
            db.mineSubmissions,
          )..where((table) => table.payloadId.equals(payloadId))).write(
            MineSubmissionsCompanion(
              state: const Value('hidden'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        } else {
          await (db.delete(
            db.mineSubmissions,
          )..where((table) => table.payloadId.equals(payloadId))).go();
          await (db.delete(
            db.mines,
          )..where((table) => table.id.equals(payloadId))).go();
        }
      });
      // La base est la source de vérité pour l'interface. Le nettoyage des
      // fichiers est volontairement non bloquant afin que la fiche se ferme
      // immédiatement, même sur un stockage Android lent.
      unawaited(_deleteLocalPhotos(photos));
      return right(unit);
    } catch (error) {
      return left(Failure.database(error.toString()));
    }
  }

  Future<void> _deleteLocalPhotos(List<MineSubmissionPhotoRow> photos) async {
    final directories = <String>{};
    for (final photo in photos) {
      final file = File(photo.path);
      directories.add(file.parent.path);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Un fichier orphelin ne doit pas faire réapparaitre la proposition.
      }
    }
    for (final path in directories) {
      try {
        final directory = Directory(path);
        if (await directory.exists() && await directory.list().isEmpty) {
          await directory.delete();
        }
      } catch (_) {
        // Un dossier non vide ou verrouillé sera nettoyé ultérieurement.
      }
    }
  }

  static String _odooDate(DateTime date) =>
      date.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
