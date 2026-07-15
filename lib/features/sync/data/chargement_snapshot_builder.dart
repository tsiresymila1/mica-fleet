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
      'fournisseur_id': c.fournisseurId,
      'statut': c.statut,
      'date_creation': _d(c.dateCreation),
      'mines': mines
          .map((m) => {
                'mine_id': m.mineId,
                'reference': m.reference,
                'couleur': m.couleur,
                'quantite_estimee': m.quantiteEstimee,
                'plaque': m.plaqueOcr,
                'lat': m.gpsLat,
                'lon': m.gpsLon,
                'gps_accuracy': m.gpsPrecision,
                'date_heure': m.dateHeure == null ? null : _d(m.dateHeure!),
                'photo': {'key': 'mine_${m.mineId}', 'hash': m.photoHash},
              })
          .toList(),
      'transbordements': trans
          .map((t) => {
                'ordre': t.ordre,
                'plaque_avant': t.plaqueAvant,
                'plaque_apres': t.plaqueApres,
                'gps_decharge': [t.gpsDechargeLat, t.gpsDechargeLon],
                'gps_recharge': [t.gpsRechargeLat, t.gpsRechargeLon],
                'distance_m': t.distanceMetres,
                'conforme': t.conforme,
                'photo_decharge': {'key': 'transb_${t.ordre}_decharge'},
                'photo_recharge': {'key': 'transb_${t.ordre}_recharge'},
              })
          .toList(),
      'arrivee': arr == null
          ? null
          : {
              'depot_id': arr.depotId,
              'chauffeur': arr.chauffeur,
              'num_permis': arr.numPermis,
              'num_lot': arr.numLot,
              'gps': [arr.gpsLat, arr.gpsLon],
              'statut_gps': arr.statutGps,
              'plaque_arrivee': arr.plaqueArrivee,
              'plaque_coherente': arr.plaqueCoherente,
              'lots': arr.lotsJson == null ? null : jsonDecode(arr.lotsJson!),
              'score_tracabilite': arr.scoreTracabilite,
              'photo_arrivee': {'key': 'arrivee'},
              'photo_permis': {'key': 'permis'},
            },
      'trajet':
          trajet.map((p) => [p.lat, p.lon, _d(p.capturedAt)]).toList(),
      'score_tracabilite': arr?.scoreTracabilite,
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
