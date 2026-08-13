import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import '../../../../core/db/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/geo.dart';
import '../../../capture/data/traceability_photo_store.dart';
import '../../../journal/data/journal_service.dart';
import '../../../sync/domain/repositories/local_sync_store.dart';
import '../../domain/entities/transbordement.dart';
import '../../domain/repositories/transport_repository.dart';

class TransportRepositoryImpl implements TransportRepository {
  final AppDatabase db;
  final LocalSyncStore syncStore;
  final JournalService journal;
  TransportRepositoryImpl(this.db, this.syncStore, this.journal);
  TraceabilityPhotoStore get _photos => TraceabilityPhotoStore(db);

  /// Remplace la chaîne de transbordements d'UN lot (le lot est indivisible :
  /// il suit son propre enchaînement de camions).
  @override
  Future<Either<Failure, Unit>> persistChaine(
    String lotId,
    List<Transbordement> chaine,
  ) async {
    try {
      await db.transaction(() async {
        await (db.delete(db.lotTraceabilityPhotos)..where(
              (t) =>
                  t.lotId.equals(lotId) &
                  (t.stage.equals(TraceabilityPhotoStage.transloadUnload) |
                      t.stage.equals(TraceabilityPhotoStage.transloadReload)),
            ))
            .go();
        await (db.delete(
          db.transbordements,
        )..where((t) => t.lotId.equals(lotId))).go();
        for (final m in chaine) {
          await db
              .into(db.transbordements)
              .insert(
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
                  photoDechargeHeadingDegrees: Value(
                    m.photoDechargeHeadingDegrees,
                  ),
                  photoDechargeHeadingAccuracy: Value(
                    m.photoDechargeHeadingAccuracy,
                  ),
                  photoDechargeHeadingReference: Value(
                    m.photoDechargeHeadingReference,
                  ),
                  photoRechargePath: Value(m.photoRechargePath),
                  photoRechargeHeadingDegrees: Value(
                    m.photoRechargeHeadingDegrees,
                  ),
                  photoRechargeHeadingAccuracy: Value(
                    m.photoRechargeHeadingAccuracy,
                  ),
                  photoRechargeHeadingReference: Value(
                    m.photoRechargeHeadingReference,
                  ),
                  distanceMetres: Value(_distance(m)),
                  conforme: Value(m.conforme),
                ),
              );
          if (m.photosDecharge != null) {
            await _photos.replace(
              lotId: lotId,
              stage: TraceabilityPhotoStage.transloadUnload,
              stageOrder: m.ordre,
              photos: m.photosDecharge!,
            );
          }
          if (m.photosRecharge != null) {
            await _photos.replace(
              lotId: lotId,
              stage: TraceabilityPhotoStage.transloadReload,
              stageOrder: m.ordre,
              photos: m.photosRecharge!,
            );
          }
        }
      });
      final payload = <String, dynamic>{
        'lot_id': lotId,
        'transloads': chaine
            .map(
              (m) => {
                'order': m.ordre,
                'plate_before': m.plaqueAvant,
                'plate_after': m.plaqueApres,
                'gps_unload': [m.gpsDechargeLat, m.gpsDechargeLon],
                'gps_reload': [m.gpsRechargeLat, m.gpsRechargeLon],
                'distance_m': _distance(m),
                'compliant': m.conforme,
              },
            )
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
    final rows =
        await (db.select(db.transbordements)
              ..where((t) => t.lotId.equals(lotId))
              ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
            .get();
    final result = <Transbordement>[];
    for (final r in rows) {
      result.add(
        Transbordement(
          ordre: r.ordre,
          plaqueAvant: r.plaqueAvant,
          plaqueApres: r.plaqueApres,
          gpsDechargeLat: r.gpsDechargeLat,
          gpsDechargeLon: r.gpsDechargeLon,
          gpsRechargeLat: r.gpsRechargeLat,
          gpsRechargeLon: r.gpsRechargeLon,
          photoDechargePath: r.photoDechargePath,
          photoDechargeHeadingDegrees: r.photoDechargeHeadingDegrees,
          photoDechargeHeadingAccuracy: r.photoDechargeHeadingAccuracy,
          photoDechargeHeadingReference: r.photoDechargeHeadingReference,
          photoRechargePath: r.photoRechargePath,
          photoRechargeHeadingDegrees: r.photoRechargeHeadingDegrees,
          photoRechargeHeadingAccuracy: r.photoRechargeHeadingAccuracy,
          photoRechargeHeadingReference: r.photoRechargeHeadingReference,
          conforme: r.conforme,
          photosDecharge: await _photos.read(
            lotId: lotId,
            stage: TraceabilityPhotoStage.transloadUnload,
            stageOrder: r.ordre,
          ),
          photosRecharge: await _photos.read(
            lotId: lotId,
            stage: TraceabilityPhotoStage.transloadReload,
            stageOrder: r.ordre,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<int> photoSchemaVersionForLot(String lotId) async {
    final lot = await (db.select(
      db.lots,
    )..where((table) => table.id.equals(lotId))).getSingleOrNull();
    return lot?.photoSchemaVersion ?? 1;
  }

  double? _distance(Transbordement m) {
    if (m.gpsDechargeLat == null || m.gpsRechargeLat == null) return null;
    return haversineMeters(
      m.gpsDechargeLat!,
      m.gpsDechargeLon!,
      m.gpsRechargeLat!,
      m.gpsRechargeLon!,
    );
  }
}
