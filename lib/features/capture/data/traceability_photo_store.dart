import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../domain/entities/captured_photo.dart';
import '../domain/entities/traceability_photos.dart';

abstract final class TraceabilityPhotoStage {
  static const mine = 'mine';
  static const transloadUnload = 'transload_unload';
  static const transloadReload = 'transload_reload';
  static const depotUnload = 'depot_unload';
}

class TraceabilityPhotoStore {
  final AppDatabase db;
  const TraceabilityPhotoStore(this.db);

  Future<void> replace({
    required String lotId,
    required String stage,
    required int stageOrder,
    required TraceabilityPhotos photos,
  }) async {
    await (db.delete(db.lotTraceabilityPhotos)..where(
          (table) =>
              table.lotId.equals(lotId) &
              table.stage.equals(stage) &
              table.stageOrder.equals(stageOrder),
        ))
        .go();
    for (final entry in photos.entries) {
      final photo = entry.photo;
      await db
          .into(db.lotTraceabilityPhotos)
          .insert(
            LotTraceabilityPhotosCompanion.insert(
              lotId: lotId,
              stage: stage,
              stageOrder: Value(stageOrder),
              role: entry.role.apiValue,
              path: photo.path,
              hash: photo.sha256,
              lat: photo.lat,
              lon: photo.lon,
              gpsAccuracy: photo.precision,
              capturedAt: photo.takenAt,
              headingDegrees: Value(photo.headingDegrees),
              headingAccuracy: Value(photo.headingAccuracy),
              headingReference: Value(photo.headingReference),
            ),
          );
    }
  }

  Future<TraceabilityPhotos?> read({
    required String lotId,
    required String stage,
    required int stageOrder,
  }) async {
    final rows =
        await (db.select(db.lotTraceabilityPhotos)..where(
              (table) =>
                  table.lotId.equals(lotId) &
                  table.stage.equals(stage) &
                  table.stageOrder.equals(stageOrder),
            ))
            .get();
    CapturedPhoto? photo(TraceabilityPhotoRole role) {
      final row = rows.where((row) => row.role == role.apiValue).firstOrNull;
      if (row == null) return null;
      return CapturedPhoto(
        path: row.path,
        sha256: row.hash,
        lat: row.lat,
        lon: row.lon,
        precision: row.gpsAccuracy,
        takenAt: row.capturedAt,
        headingDegrees: row.headingDegrees,
        headingAccuracy: row.headingAccuracy,
        headingReference: row.headingReference,
      );
    }

    final plate = photo(TraceabilityPhotoRole.plate);
    final mica = photo(TraceabilityPhotoRole.mica);
    final truck = photo(TraceabilityPhotoRole.truckWithMica);
    if (plate == null || mica == null || truck == null) return null;
    return TraceabilityPhotos(plate: plate, mica: mica, truckWithMica: truck);
  }
}
