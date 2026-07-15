import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../journal/data/journal_service.dart';
import '../../../sync/data/chargement_snapshot_builder.dart';
import '../../../sync/domain/entities/sync_operation.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/arrivee_depot.dart';
import '../../domain/entities/depot.dart';
import '../../domain/repositories/depot_repository.dart';

class DepotRepositoryImpl implements DepotRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final JournalService journal;
  DepotRepositoryImpl(this.db, this.syncStore, this.journal);

  ChargementSnapshotBuilder get _snapshot => ChargementSnapshotBuilder(db);

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
      // Envoi UNIQUE : le chargement est complet → on construit le snapshot
      // global (mines + transbordements + arrivée + trajet) et on l'enfile
      // en une seule opération de sync.
      final snap = await _snapshot.build(a.chargementId);
      if (snap != null) {
        await syncStore.enqueue(SyncOperation(
          opId: snap.deviceUuid, // stable → idempotence
          entityType: 'chargement',
          entityId: a.chargementId,
          opType: SyncOpType.create,
          payload: snap.payload,
          createdAt: DateTime.now(),
          agentLogin: snap.agentLogin,
          gpsLat: snap.gpsLat,
          gpsLon: snap.gpsLon,
          gpsAccuracy: snap.gpsAccuracy,
        ));
        await journal.append(
            'arrivee_depot', a.chargementId, jsonEncode(snap.payload));
      }
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
