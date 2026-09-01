import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../domain/update_readiness_repository.dart';

class DriftUpdateReadinessRepository implements UpdateReadinessRepository {
  final AppDatabase db;

  const DriftUpdateReadinessRepository(this.db);

  @override
  Future<int> unsyncedDataCount() async {
    final queueCountExpression = db.syncQueue.opId.count();
    final queueQuery = db.selectOnly(db.syncQueue)
      ..addColumns([queueCountExpression])
      ..where(db.syncQueue.status.equals('synced').not());
    final queueCount = await queueQuery
        .map((row) => row.read(queueCountExpression) ?? 0)
        .getSingle();

    // Un lot en route n'a pas encore d'opération dans sync_queue. Il reste
    // néanmoins une donnée locale à protéger tant que toutes ses photos ne
    // sont pas confirmées côté serveur.
    final localLotCountExpression = db.lots.id.count();
    final localLotQuery = db.selectOnly(db.lots)
      ..addColumns([localLotCountExpression])
      ..where(
        db.lots.remoteOnly.equals(false) & db.lots.photosUploaded.equals(false),
      );
    final localLotCount = await localLotQuery
        .map((row) => row.read(localLotCountExpression) ?? 0)
        .getSingle();

    // Une proposition peut exister avant la création de son opération de
    // synchronisation. Les états serveur (validation, approuvé, rejeté) ne
    // bloquent pas la mise à jour car leurs données sont déjà distantes.
    final mineSubmissionCountExpression = db.mineSubmissions.payloadId.count();
    final mineSubmissionQuery = db.selectOnly(db.mineSubmissions)
      ..addColumns([mineSubmissionCountExpression])
      ..where(
        db.mineSubmissions.state.isIn([
          'local_pending',
          'awaiting_attachments',
        ]),
      );
    final mineSubmissionCount = await mineSubmissionQuery
        .map((row) => row.read(mineSubmissionCountExpression) ?? 0)
        .getSingle();

    return queueCount + localLotCount + mineSubmissionCount;
  }
}
