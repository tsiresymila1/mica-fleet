import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/geo.dart';
import '../../../journal/data/journal_service.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/transbordement.dart';
import '../../domain/repositories/transport_repository.dart';

class TransportRepositoryImpl implements TransportRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final JournalService journal;
  TransportRepositoryImpl(this.db, this.syncStore, this.journal);

  @override
  Future<Either<Failure, Unit>> persistChaine(
      String chargementId, List<Transbordement> chaine) async {
    try {
      await db.transaction(() async {
        await (db.delete(db.transbordements)
              ..where((t) => t.chargementId.equals(chargementId)))
            .go();
        for (final m in chaine) {
          await db.into(db.transbordements).insert(
                TransbordementsCompanion.insert(
                  chargementId: chargementId,
                  ordre: m.ordre,
                  plaqueAvant: Value(m.plaqueAvant),
                  plaqueApres: Value(m.plaqueApres),
                  gpsDechargeLat: Value(m.gpsDechargeLat),
                  gpsDechargeLon: Value(m.gpsDechargeLon),
                  gpsRechargeLat: Value(m.gpsRechargeLat),
                  gpsRechargeLon: Value(m.gpsRechargeLon),
                  distanceMetres: Value(_distance(m)),
                  conforme: Value(m.conforme),
                ),
              );
        }
      });
      final payload = <String, dynamic>{
        'chargement_id': chargementId,
        'maillons': chaine
            .map((m) => {
                  'ordre': m.ordre,
                  'plaque_avant': m.plaqueAvant,
                  'plaque_apres': m.plaqueApres,
                  'gps_decharge': [m.gpsDechargeLat, m.gpsDechargeLon],
                  'gps_recharge': [m.gpsRechargeLat, m.gpsRechargeLon],
                  'distance_m': _distance(m),
                  'conforme': m.conforme,
                })
            .toList(),
      };
      // Sync unique : envoyée à l'arrivée. Ici on journalise seulement.
      await journal.append('transbordement', chargementId, jsonEncode(payload));
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<List<Transbordement>> chaineFor(String chargementId) async {
    final rows = await (db.select(db.transbordements)
          ..where((t) => t.chargementId.equals(chargementId))
          ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
        .get();
    return rows
        .map((r) => Transbordement(
              ordre: r.ordre,
              plaqueAvant: r.plaqueAvant,
              plaqueApres: r.plaqueApres,
              gpsDechargeLat: r.gpsDechargeLat,
              gpsDechargeLon: r.gpsDechargeLon,
              gpsRechargeLat: r.gpsRechargeLat,
              gpsRechargeLon: r.gpsRechargeLon,
              conforme: r.conforme,
            ))
        .toList();
  }

  double? _distance(Transbordement m) {
    if (m.gpsDechargeLat == null || m.gpsRechargeLat == null) return null;
    return haversineMeters(m.gpsDechargeLat!, m.gpsDechargeLon!,
        m.gpsRechargeLat!, m.gpsRechargeLon!);
  }
}
