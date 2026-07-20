import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../journal/data/journal_service.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/chargement.dart';
import '../../domain/repositories/loading_repository.dart';

class LoadingRepositoryImpl implements LoadingRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final JournalService journal;
  final _uuid = const Uuid();
  LoadingRepositoryImpl(this.db, this.syncStore, this.journal);

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
                lotReference: Value(c.lotReference),
              ),
            );
        for (final l in c.lots) {
          await db.into(db.lots).insertOnConflictUpdate(
                LotsCompanion.insert(
                  id: l.id,
                  sessionId: c.id,
                  mineId: l.mineId,
                  reference: Value(l.reference),
                  couleur: Value(l.couleur),
                  quantiteEstimee: Value(l.quantiteEstimee),
                  plaqueDepart: Value(l.plaqueDepart),
                  gpsLat: Value(l.photo?.lat),
                  gpsLon: Value(l.photo?.lon),
                  gpsPrecision: Value(l.photo?.precision),
                  photoPath: Value(l.photo?.path),
                  photoHash: Value(l.photo?.sha256),
                  dateHeure: Value(l.photo?.takenAt),
                  statut: const Value('en_cours'),
                  // Idempotence sync : un device_uuid stable PAR LOT.
                  deviceUuid: Value(l.deviceUuid ?? _uuid.v4()),
                ),
              );
        }
      });
      final payload = <String, dynamic>{
        'id': c.id,
        'supplier_id': c.fournisseurId,
        'lot_reference': c.lotReference,
        'lots': c.lots
            .map((l) => {
                  'lot_id': l.id,
                  'mine_id': l.mineId,
                  'color': l.couleur,
                  'estimated_quantity': l.quantiteEstimee,
                  'plate': l.plaqueDepart,
                  'hash': l.photo?.sha256,
                })
            .toList(),
      };
      // Sync unique PAR LOT : l'envoi part à l'arrivée de chaque lot.
      await journal.append('chargement', c.id, jsonEncode(payload));
      return right(c);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteChargement(String chargementId) async {
    try {
      final lots = await (db.select(db.lots)
            ..where((t) => t.sessionId.equals(chargementId)))
          .get();
      final lotIds = lots.map((l) => l.id).toList();
      // Refuse si un lot est déjà arrivé au dépôt (finalisé).
      for (final id in lotIds) {
        final arr = await (db.select(db.arriveesDepot)
              ..where((t) => t.lotId.equals(id)))
            .getSingleOrNull();
        if (arr != null) {
          return left(const Failure.validation(
              'Un lot est déjà arrivé au dépôt — suppression impossible'));
        }
      }
      await db.transaction(() async {
        for (final id in lotIds) {
          await (db.delete(db.transbordements)
                ..where((t) => t.lotId.equals(id)))
              .go();
          await (db.delete(db.syncQueue)..where((t) => t.entityId.equals(id)))
              .go();
        }
        await (db.delete(db.lots)
              ..where((t) => t.sessionId.equals(chargementId)))
            .go();
        await (db.delete(db.trajetPoints)
              ..where((t) => t.chargementId.equals(chargementId)))
            .go();
        await (db.delete(db.syncQueue)
              ..where((t) => t.entityId.equals(chargementId)))
            .go();
        await (db.delete(db.chargements)
              ..where((t) => t.id.equals(chargementId)))
            .go();
      });
      await journal.append(
          'chargement_supprime', chargementId, '{"id":"$chargementId"}');
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }
}
