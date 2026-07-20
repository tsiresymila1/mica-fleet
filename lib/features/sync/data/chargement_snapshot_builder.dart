import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';

/// Snapshot complet d'UN LOT pour l'envoi unique (submit) : mine d'origine +
/// transbordements du lot + arrivée + trace GPS de la session.
/// Les photos sont déclarées par clé + hash (binaires uploadés à part).
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
  LotSnapshotBuilder(this.db);

  Future<LotSnapshot?> build(String lotId) async {
    final lot =
        await (db.select(db.lots)..where((t) => t.id.equals(lotId)))
            .getSingleOrNull();
    if (lot == null) return null;

    final session = await (db.select(db.chargements)
          ..where((t) => t.id.equals(lot.sessionId)))
        .getSingleOrNull();
    final trans = await (db.select(db.transbordements)
          ..where((t) => t.lotId.equals(lotId))
          ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
        .get();
    final arr = await (db.select(db.arriveesDepot)
          ..where((t) => t.lotId.equals(lotId)))
        .getSingleOrNull();
    final trajet = await (db.select(db.trajetPoints)
          ..where((t) => t.chargementId.equals(lot.sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
        .get();

    final payload = <String, dynamic>{
      // `id` = identifiant du payload = identifiant du LOT (1 payload = 1 lot).
      'id': lot.id,
      'session_id': lot.sessionId, // lots partis ensemble
      'supplier_id': session?.fournisseurId,
      'lot_reference': session?.lotReference,
      'status': lot.statut,
      'created_at': session == null ? null : _d(session.dateCreation),

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
        'photo': {'key': 'mine', 'hash': lot.photoHash},
      },

      // Camions successifs ayant porté CE lot.
      'transloads': trans
          .map((t) => {
                'order': t.ordre,
                'plate_before': t.plaqueAvant,
                'plate_after': t.plaqueApres,
                'gps_unload': [t.gpsDechargeLat, t.gpsDechargeLon],
                'gps_reload': [t.gpsRechargeLat, t.gpsRechargeLon],
                'distance_m': t.distanceMetres,
                'compliant': t.conforme,
                'photo_unload': {'key': 'transload_${t.ordre}_unload'},
                'photo_reload': {'key': 'transload_${t.ordre}_reload'},
              })
          .toList(),

      'arrival': arr == null
          ? null
          : {
              'depot_id': _id(arr.depotId),
              'driver': arr.chauffeur,
              'license_number': arr.numPermis,
              'lot_number': arr.numLot,
              // Odoo indexe aussi le numéro par couleur de mica.
              'lots': {lot.couleur ?? 'lot': arr.numLot},
              'gps': [arr.gpsLat, arr.gpsLon],
              'gps_status': arr.statutGps,
              'plate_arrival': arr.plaqueArrivee,
              'plate_consistent': arr.plaqueCoherente,
              'traceability_score': arr.scoreTracabilite,
              'photo_arrival': {'key': 'arrival'},
              'photo_license': {'key': 'license'},
            },

      'track': trajet.map((p) => [p.lat, p.lon, _d(p.capturedAt)]).toList(),
      'traceability_score': lot.score ?? arr?.scoreTracabilite,
    };

    return (
      deviceUuid: lot.deviceUuid ?? lot.id,
      agentLogin: session?.fournisseurId,
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

  static String _d(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
