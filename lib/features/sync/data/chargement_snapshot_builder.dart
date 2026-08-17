import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../capture/data/traceability_photo_store.dart';
import '../../capture/domain/entities/captured_photo.dart';
import '../../capture/domain/entities/traceability_photos.dart';

/// Snapshot complet d'UN LOT pour l'envoi unique (submit) : mine d'origine +
/// transbordements du lot + arrivée + trace GPS de la session.
/// Les photos déclarent leur clé, hash disponible et cap magnétique ; les
/// binaires sont uploadés séparément.
typedef LotSnapshot = ({
  String deviceUuid,
  String? agentLogin,
  double? gpsLat,
  double? gpsLon,
  double? gpsAccuracy,
  Map<String, dynamic> payload,
});

class LotSnapshotBuilder {
  final AppDatabase db;
  final _uuid = const Uuid();
  TraceabilityPhotoStore get _photos => TraceabilityPhotoStore(db);
  LotSnapshotBuilder(this.db);

  Future<LotSnapshot?> build(String lotId) async {
    final lot = await (db.select(
      db.lots,
    )..where((t) => t.id.equals(lotId))).getSingleOrNull();
    if (lot == null) return null;

    final session = await (db.select(
      db.chargements,
    )..where((t) => t.id.equals(lot.sessionId))).getSingleOrNull();
    if (session == null) return null;

    // Les références MICA restent les clés locales/UI. L'API reçoit des UUID
    // stables, persistés une seule fois et partagés par tous les lots d'une
    // même session.
    final payloadUuid = lot.payloadUuid ?? _uuid.v4();
    final sessionUuid = session.sessionUuid ?? _uuid.v4();
    if (lot.payloadUuid == null || session.sessionUuid == null) {
      await db.transaction(() async {
        if (lot.payloadUuid == null) {
          await (db.update(db.lots)..where((t) => t.id.equals(lot.id))).write(
            LotsCompanion(payloadUuid: Value(payloadUuid)),
          );
        }
        if (session.sessionUuid == null) {
          await (db.update(db.chargements)
                ..where((t) => t.id.equals(session.id)))
              .write(ChargementsCompanion(sessionUuid: Value(sessionUuid)));
        }
      });
    }

    final trans =
        await (db.select(db.transbordements)
              ..where((t) => t.lotId.equals(lotId))
              ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
            .get();
    final arr = await (db.select(
      db.arriveesDepot,
    )..where((t) => t.lotId.equals(lotId))).getSingleOrNull();
    final trajet =
        await (db.select(db.trajetPoints)
              ..where((t) => t.chargementId.equals(lot.sessionId))
              ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
            .get();
    final photoV2 = lot.photoSchemaVersion >= 2;
    final minePhotos = photoV2
        ? await _photos.read(
            lotId: lotId,
            stage: TraceabilityPhotoStage.mine,
            stageOrder: 0,
          )
        : null;
    final transloadPayloads = <Map<String, dynamic>>[];
    for (final t in trans) {
      final unload = photoV2
          ? await _photos.read(
              lotId: lotId,
              stage: TraceabilityPhotoStage.transloadUnload,
              stageOrder: t.ordre,
            )
          : null;
      final reload = photoV2
          ? await _photos.read(
              lotId: lotId,
              stage: TraceabilityPhotoStage.transloadReload,
              stageOrder: t.ordre,
            )
          : null;
      transloadPayloads.add({
        'order': t.ordre,
        'plate_before': t.plaqueAvant,
        'plate_after': t.plaqueApres,
        'gps_unload': [t.gpsDechargeLat, t.gpsDechargeLon],
        'gps_reload': [t.gpsRechargeLat, t.gpsRechargeLon],
        'distance_m': t.distanceMetres,
        'compliant': t.conforme,
        if (photoV2)
          'photos_unload': unload == null
              ? null
              : _photoSetMetadata('transload_${t.ordre}_unload', unload)
        else
          'photo_unload': _photoMetadata(
            'transload_${t.ordre}_unload',
            headingDegrees: t.photoDechargeHeadingDegrees,
            headingAccuracy: t.photoDechargeHeadingAccuracy,
            headingReference: t.photoDechargeHeadingReference,
          ),
        if (photoV2)
          'photos_reload': reload == null
              ? null
              : _photoSetMetadata('transload_${t.ordre}_reload', reload)
        else
          'photo_reload': _photoMetadata(
            'transload_${t.ordre}_reload',
            headingDegrees: t.photoRechargeHeadingDegrees,
            headingAccuracy: t.photoRechargeHeadingAccuracy,
            headingReference: t.photoRechargeHeadingReference,
          ),
      });
    }
    final depotPhotos = photoV2 && arr != null
        ? await _photos.read(
            lotId: lotId,
            stage: TraceabilityPhotoStage.depotUnload,
            stageOrder: 0,
          )
        : null;

    final payload = <String, dynamic>{
      // Identifiants d'intégration UUID. Les références MICA restent locales.
      'id': payloadUuid,
      'session_id': sessionUuid,
      'supplier_id': session.fournisseurId,
      if (lot.photoSchemaVersion < 3) 'lot_reference': session.lotReference,
      'photo_schema_version': lot.photoSchemaVersion,
      'status': lot.statut,
      'created_at': _d(session.dateCreation),

      // Origine : UNE mine, quantité figée au départ (lot indivisible).
      'mine': {
        'mine_id': _id(lot.mineId),
        'reference': lot.reference,
        'color': lot.couleur,
        'estimated_quantity': lot.quantiteEstimee,
        'plate': lot.plaqueDepart,
        'lat': lot.gpsLat,
        'lon': lot.gpsLon,
        'gps_accuracy': lot.gpsPrecision,
        'captured_at': lot.dateHeure == null ? null : _d(lot.dateHeure!),
        if (photoV2)
          'photos': minePhotos == null
              ? null
              : _photoSetMetadata('mine', minePhotos)
        else
          'photo': _photoMetadata(
            'mine',
            hash: lot.photoHash,
            headingDegrees: lot.photoHeadingDegrees,
            headingAccuracy: lot.photoHeadingAccuracy,
            headingReference: lot.photoHeadingReference,
          ),
      },

      // Camions successifs ayant porté CE lot.
      'transloads': transloadPayloads,

      'arrival': arr == null
          ? null
          : {
              if (lot.photoSchemaVersion < 3 && arr.depotId != null)
                'depot_id': _id(arr.depotId!),
              'driver': arr.chauffeur,
              'license_number': arr.numPermis,
              if (lot.photoSchemaVersion < 3) 'lot_number': arr.numLot,
              if (lot.photoSchemaVersion < 3)
                'lots': {lot.couleur ?? 'lot': arr.numLot},
              'gps': [arr.gpsLat, arr.gpsLon],
              'gps_status': arr.statutGps,
              'plate_arrival': arr.plaqueArrivee,
              'plate_consistent': arr.plaqueCoherente,
              'traceability_score': arr.scoreTracabilite,
              if (photoV2)
                'photos_unload': depotPhotos == null
                    ? null
                    : _photoSetMetadata('depot_unload', depotPhotos)
              else
                'photo_arrival': _photoMetadata(
                  'arrival',
                  headingDegrees: arr.photoArriveeHeadingDegrees,
                  headingAccuracy: arr.photoArriveeHeadingAccuracy,
                  headingReference: arr.photoArriveeHeadingReference,
                ),
              'photo_license': _photoMetadata(
                'license',
                headingDegrees: arr.photoPermisHeadingDegrees,
                headingAccuracy: arr.photoPermisHeadingAccuracy,
                headingReference: arr.photoPermisHeadingReference,
              ),
            },

      'track': trajet.map((p) => [p.lat, p.lon, _d(p.capturedAt)]).toList(),
      'traceability_score': lot.score ?? arr?.scoreTracabilite,
    };

    return (
      deviceUuid: lot.deviceUuid ?? lot.id,
      agentLogin: session.fournisseurId,
      gpsLat: lot.gpsLat,
      gpsLon: lot.gpsLon,
      gpsAccuracy: lot.gpsPrecision,
      payload: payload,
    );
  }

  /// Les ids du référentiel Odoo sont numériques ; on les stocke en texte.
  /// On renvoie l'entier quand c'est possible, sinon la chaîne telle quelle
  /// (jeux de données de démo type « M001 »).
  static dynamic _id(String v) => int.tryParse(v) ?? v;

  static Map<String, dynamic> _photoMetadata(
    String key, {
    String? hash,
    double? headingDegrees,
    double? headingAccuracy,
    String? headingReference,
  }) => {
    'key': key,
    'hash': ?hash,
    'heading_deg': ?headingDegrees,
    'heading_accuracy': ?headingAccuracy,
    'heading_reference': ?headingReference,
  };

  static Map<String, dynamic> _photoSetMetadata(
    String keyPrefix,
    TraceabilityPhotos photos,
  ) => {
    for (final entry in photos.entries)
      entry.role.apiValue: _capturedPhotoMetadata(
        '${keyPrefix}_${entry.role.apiValue}',
        entry.photo,
      ),
  };

  static Map<String, dynamic> _capturedPhotoMetadata(
    String key,
    CapturedPhoto photo,
  ) => {
    'key': key,
    'hash': photo.sha256,
    'lat': photo.lat,
    'lon': photo.lon,
    'gps_accuracy': photo.precision,
    'captured_at': _d(photo.takenAt),
    'heading_deg': ?photo.headingDegrees,
    'heading_accuracy': ?photo.headingAccuracy,
    'heading_reference': ?photo.headingReference,
  };

  static String _d(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
