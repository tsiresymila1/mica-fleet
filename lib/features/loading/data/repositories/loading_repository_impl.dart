import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../sync/domain/entities/sync_operation.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/chargement.dart';
import '../../domain/repositories/loading_repository.dart';

class LoadingRepositoryImpl implements LoadingRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final _uuid = const Uuid();
  LoadingRepositoryImpl(this.db, this.syncStore);

  @override
  Future<int> nextSequence(int year) async {
    final rows = await db.select(db.chargements).get();
    final n = rows.where((c) => c.id.startsWith('MICA-$year-')).length;
    return n + 1;
  }

  @override
  Future<Either<Failure, Chargement>> persist(Chargement c) async {
    try {
      await db.transaction(() async {
        await db.into(db.chargements).insertOnConflictUpdate(
              ChargementsCompanion.insert(
                id: c.id,
                fournisseurId: c.fournisseurId,
                dateCreation: c.dateCreation,
                statut: Value(c.statut),
              ),
            );
        for (final m in c.mines) {
          await db.into(db.mineChargements).insert(
                MineChargementsCompanion.insert(
                  chargementId: c.id,
                  mineId: m.mineId,
                  reference: Value(m.reference),
                  couleur: Value(m.couleur),
                  quantiteEstimee: Value(m.quantiteEstimee),
                  plaqueOcr: Value(m.plaqueOcr),
                  gpsLat: Value(m.photo?.lat),
                  gpsLon: Value(m.photo?.lon),
                  gpsPrecision: Value(m.photo?.precision),
                  photoPath: Value(m.photo?.path),
                  photoHash: Value(m.photo?.sha256),
                  dateHeure: Value(m.photo?.takenAt),
                ),
              );
        }
      });
      await syncStore.enqueue(SyncOperation(
        opId: _uuid.v4(),
        entityType: 'chargement',
        entityId: c.id,
        opType: SyncOpType.create,
        payload: {
          'id': c.id,
          'fournisseur_id': c.fournisseurId,
          'statut': c.statut,
          'mines': c.mines
              .map((m) => {
                    'mine_id': m.mineId,
                    'reference': m.reference,
                    'couleur': m.couleur,
                    'quantite_estimee': m.quantiteEstimee,
                    'plaque': m.plaqueOcr,
                    'lat': m.photo?.lat,
                    'lon': m.photo?.lon,
                    'hash': m.photo?.sha256,
                  })
              .toList(),
        },
        createdAt: DateTime.now(),
      ));
      return right(c);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }
}
