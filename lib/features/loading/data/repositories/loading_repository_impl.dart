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
                deviceUuid: Value(_uuid.v4()), // stable, pour la sync unique
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
      final payload = <String, dynamic>{
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
      };
      // Sync unique : pas d'envoi à cette étape. Le submit complet part à
      // l'arrivée au dépôt (voir DepotRepositoryImpl). On journalise seulement.
      await journal.append('chargement', c.id, jsonEncode(payload));
      return right(c);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteChargement(String chargementId) async {
    try {
      // Refuse si déjà arrivé au dépôt (finalisé).
      final arrivee = await (db.select(db.arriveesDepot)
            ..where((t) => t.chargementId.equals(chargementId)))
          .getSingleOrNull();
      if (arrivee != null) {
        return left(const Failure.validation(
            'Chargement déjà arrivé au dépôt — suppression impossible'));
      }
      await db.transaction(() async {
        await (db.delete(db.mineChargements)
              ..where((t) => t.chargementId.equals(chargementId)))
            .go();
        await (db.delete(db.transbordements)
              ..where((t) => t.chargementId.equals(chargementId)))
            .go();
        await (db.delete(db.syncQueue)
              ..where((t) => t.entityId.equals(chargementId)))
            .go();
        await (db.delete(db.chargements)
              ..where((t) => t.id.equals(chargementId)))
            .go();
      });
      await journal.append('chargement_supprime', chargementId,
          '{"id":"$chargementId"}');
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }
}
