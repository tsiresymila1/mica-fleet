import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../journal/data/journal_service.dart';
import '../../../sync/domain/entities/sync_operation.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/arrivee_depot.dart';
import '../../domain/entities/depot.dart';
import '../../domain/repositories/depot_repository.dart';

class DepotRepositoryImpl implements DepotRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final JournalService journal;
  final _uuid = const Uuid();
  DepotRepositoryImpl(this.db, this.syncStore, this.journal);

  @override
  Future<List<Depot>> activeDepots() async {
    final rows =
        await (db.select(db.depots)..where((d) => d.actif.equals(true))).get();
    return rows
        .map((r) => Depot(
              id: r.id,
              nom: r.nom,
              lat: r.lat,
              lon: r.lon,
              rayonMetres: r.rayonMetres,
              actif: r.actif,
            ))
        .toList();
  }

  @override
  Future<Either<Failure, Unit>> persistArrivee(ArriveeDepot a) async {
    try {
      await db.into(db.arriveesDepot).insertOnConflictUpdate(
            ArriveesDepotCompanion.insert(
              chargementId: a.chargementId,
              depotId: a.depotId,
              chauffeur: a.chauffeur,
              numPermis: a.numPermis,
              numLot: a.numLot,
              gpsLat: a.gpsLat,
              gpsLon: a.gpsLon,
              statutGps: a.statutGps,
              photoPermisPath: Value(a.photoPermisPath),
              photoArriveePath: Value(a.photoArriveePath),
              plaqueArrivee: Value(a.plaqueArrivee),
              plaqueCoherente: Value(a.plaqueCoherente),
              scoreTracabilite: Value(a.scoreTracabilite),
              lotsJson: Value(a.lotsJson),
            ),
          );
      final payload = <String, dynamic>{
        'chargement_id': a.chargementId,
        'depot_id': a.depotId,
        'chauffeur': a.chauffeur,
        'num_permis': a.numPermis,
        'num_lot': a.numLot,
        'gps': [a.gpsLat, a.gpsLon],
        'statut_gps': a.statutGps,
        'plaque_arrivee': a.plaqueArrivee,
        'plaque_coherente': a.plaqueCoherente,
        'score_tracabilite': a.scoreTracabilite,
        'lots': a.lotsJson,
      };
      await syncStore.enqueue(SyncOperation(
        opId: _uuid.v4(),
        entityType: 'arrivee_depot',
        entityId: a.chargementId,
        opType: SyncOpType.update,
        payload: payload,
        createdAt: DateTime.now(),
        gpsLat: a.gpsLat,
        gpsLon: a.gpsLon,
      ));
      await journal.append('arrivee_depot', a.chargementId, jsonEncode(payload));
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<ChargementResume> chargementResume(String chargementId) async {
    final mines = await (db.select(db.mineChargements)
          ..where((t) => t.chargementId.equals(chargementId)))
        .get();
    final charg = await (db.select(db.chargements)
          ..where((t) => t.id.equals(chargementId)))
        .getSingleOrNull();
    final couleurs = mines
        .map((m) => m.couleur)
        .whereType<String>()
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList();
    return (
      nbMines: mines.length,
      cree: charg?.dateCreation,
      plaque: mines.isNotEmpty ? mines.first.plaqueOcr : null,
      couleurs: couleurs,
    );
  }
}
