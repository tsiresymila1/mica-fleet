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

  LotSnapshotBuilder get _snapshot => LotSnapshotBuilder(db);

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
      await db.transaction(() async {
        await db.into(db.arriveesDepot).insertOnConflictUpdate(
              ArriveesDepotCompanion.insert(
                lotId: a.lotId,
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
              ),
            );
        // Le lot est arrivé : statut + score figés sur le lot.
        await (db.update(db.lots)..where((t) => t.id.equals(a.lotId))).write(
          LotsCompanion(
            statut: const Value('arrive'),
            score: Value(a.scoreTracabilite),
          ),
        );
      });

      // Envoi UNIQUE par LOT : snapshot complet du lot (mine + transbordements
      // + arrivée + trajet) en une seule opération de sync.
      final snap = await _snapshot.build(a.lotId);
      if (snap != null) {
        await syncStore.enqueue(SyncOperation(
          opId: snap.deviceUuid, // stable par lot → idempotence
          entityType: 'lot',
          entityId: a.lotId,
          opType: SyncOpType.create,
          payload: snap.payload,
          createdAt: DateTime.now(),
          agentLogin: snap.agentLogin,
          gpsLat: snap.gpsLat,
          gpsLon: snap.gpsLon,
          gpsAccuracy: snap.gpsAccuracy,
        ));
        await journal.append('arrivee_depot', a.lotId, jsonEncode(snap.payload));
      }
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<LotResume?> lotResume(String lotId) async {
    final l = await (db.select(db.lots)..where((t) => t.id.equals(lotId)))
        .getSingleOrNull();
    if (l == null) return null;
    final s = await (db.select(db.chargements)
          ..where((t) => t.id.equals(l.sessionId)))
        .getSingleOrNull();
    return (
      sessionId: l.sessionId,
      mineId: l.mineId,
      cree: s?.dateCreation,
      plaqueDepart: l.plaqueDepart,
      couleur: l.couleur,
    );
  }

  @override
  Future<List<({String id, String mineId, String? couleur})>> lotsEnCours(
      String sessionId) async {
    final rows = await (db.select(db.lots)
          ..where((t) =>
              t.sessionId.equals(sessionId) & t.statut.equals('en_cours')))
        .get();
    return rows
        .map((l) => (id: l.id, mineId: l.mineId, couleur: l.couleur))
        .toList();
  }
}
