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

  /// Remplace la chaîne de transbordements d'UN lot (le lot est indivisible :
  /// il suit son propre enchaînement de camions).
  @override
  Future<Either<Failure, Unit>> persistChaine(
      String lotId, List<Transbordement> chaine) async {
    try {
      await db.transaction(() async {
        await (db.delete(db.transbordements)..where((t) => t.lotId.equals(lotId)))
            .go();
        for (final m in chaine) {
          await db.into(db.transbordements).insert(
                TransbordementsCompanion.insert(
                  lotId: lotId,
                  ordre: m.ordre,
                  plaqueAvant: Value(m.plaqueAvant),
                  plaqueApres: Value(m.plaqueApres),
                  gpsDechargeLat: Value(m.gpsDechargeLat),
                  gpsDechargeLon: Value(m.gpsDechargeLon),
                  gpsRechargeLat: Value(m.gpsRechargeLat),
                  gpsRechargeLon: Value(m.gpsRechargeLon),
                  photoDechargePath: Value(m.photoDechargePath),
                  photoRechargePath: Value(m.photoRechargePath),
                  distanceMetres: Value(_distance(m)),
                  conforme: Value(m.conforme),
                ),
              );
        }
      });
      final payload = <String, dynamic>{
        'lot_id': lotId,
        'transloads': chaine
            .map((m) => {
                  'order': m.ordre,
                  'plate_before': m.plaqueAvant,
                  'plate_after': m.plaqueApres,
                  'gps_unload': [m.gpsDechargeLat, m.gpsDechargeLon],
                  'gps_reload': [m.gpsRechargeLat, m.gpsRechargeLon],
                  'distance_m': _distance(m),
                  'compliant': m.conforme,
                })
            .toList(),
      };
      // Sync unique : envoyée à l'arrivée du lot. Ici on journalise seulement.
      await journal.append('transbordement', lotId, jsonEncode(payload));
      return right(unit);
    } catch (e) {
      return left(Failure.database(e.toString()));
    }
  }

  @override
  Future<List<Transbordement>> chaineFor(String lotId) async {
    final rows = await (db.select(db.transbordements)
          ..where((t) => t.lotId.equals(lotId))
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
              photoDechargePath: r.photoDechargePath,
              photoRechargePath: r.photoRechargePath,
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
