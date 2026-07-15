import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/db/app_database.dart';

/// Snapshot complet d'un chargement pour l'envoi unique (submit terrain_api) :
/// mines + transbordements + arrivée + trajet, avec clés de photo + hash.
typedef ChargementSnapshot = ({
  String deviceUuid,
  String? agentLogin,
  double? gpsLat,
  double? gpsLon,
  double? gpsAccuracy,
  Map<String, dynamic> payload,
});

class ChargementSnapshotBuilder {
  final AppDatabase db;
  ChargementSnapshotBuilder(this.db);

  Future<ChargementSnapshot?> build(String chargementId) async {
    final c = await (db.select(db.chargements)
          ..where((t) => t.id.equals(chargementId)))
        .getSingleOrNull();
    if (c == null) return null;

    final mines = await (db.select(db.mineChargements)
          ..where((t) => t.chargementId.equals(chargementId)))
        .get();
    final trans = await (db.select(db.transbordements)
          ..where((t) => t.chargementId.equals(chargementId))
          ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
        .get();
    final arr = await (db.select(db.arriveesDepot)
          ..where((t) => t.chargementId.equals(chargementId)))
        .getSingleOrNull();
    final trajet = await (db.select(db.trajetPoints)
          ..where((t) => t.chargementId.equals(chargementId))
          ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
        .get();

    final payload = <String, dynamic>{
      'id': c.id,
      'supplier_id': c.fournisseurId,
      'lot_reference': c.lotReference, // regroupement Odoo (optionnel, nullable)
      'status': c.statut,
      'created_at': _d(c.dateCreation),
      'mines': mines
          .map((m) => {
                'mine_id': m.mineId,
                'reference': m.reference,
                'color': m.couleur,
                'estimated_quantity': m.quantiteEstimee,
                'plate': m.plaqueOcr,
                'lat': m.gpsLat,
                'lon': m.gpsLon,
                'gps_accuracy': m.gpsPrecision,
                'captured_at': m.dateHeure == null ? null : _d(m.dateHeure!),
                'photo': {'key': 'mine_${m.mineId}', 'hash': m.photoHash},
              })
          .toList(),
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
              'depot_id': arr.depotId,
              'driver': arr.chauffeur,
              'license_number': arr.numPermis,
              'lot_number': arr.numLot,
              'gps': [arr.gpsLat, arr.gpsLon],
              'gps_status': arr.statutGps,
              'plate_arrival': arr.plaqueArrivee,
              'plate_consistent': arr.plaqueCoherente,
              'lots': arr.lotsJson == null ? null : jsonDecode(arr.lotsJson!),
              'traceability_score': arr.scoreTracabilite,
              'photo_arrival': {'key': 'arrival'},
              'photo_license': {'key': 'license'},
            },
      'track': trajet.map((p) => [p.lat, p.lon, _d(p.capturedAt)]).toList(),
      'traceability_score': arr?.scoreTracabilite,
    };

    final firstMine = mines.isNotEmpty ? mines.first : null;
    return (
      deviceUuid: c.deviceUuid ?? c.id,
      agentLogin: c.fournisseurId,
      gpsLat: firstMine?.gpsLat,
      gpsLon: firstMine?.gpsLon,
      gpsAccuracy: firstMine?.gpsPrecision,
      payload: payload,
    );
  }

  static String _d(DateTime d) =>
      d.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first;
}
