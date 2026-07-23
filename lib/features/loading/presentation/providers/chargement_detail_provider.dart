import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';

class TransLine {
  final int ordre;
  final String? plaqueAvant, plaqueApres, photoDecharge, photoRecharge;
  final bool conforme;
  const TransLine(this.ordre, this.plaqueAvant, this.plaqueApres, this.conforme,
      this.photoDecharge, this.photoRecharge);
}

class ArriveeLine {
  final String depotId, chauffeur, numPermis, numLot, statutGps;
  final String? plaqueArrivee, photoArrivee, photoPermis;
  final bool plaqueCoherente;
  final int? score;
  const ArriveeLine(this.depotId, this.chauffeur, this.numPermis, this.numLot,
      this.statutGps, this.plaqueArrivee, this.plaqueCoherente, this.score,
      this.photoArrivee, this.photoPermis);
}

/// Détail d'UN LOT : origine (une mine), ses transbordements, son arrivée.
class LotDetail {
  final String id;
  final String sessionId;
  final String mineId;
  final String? reference, couleur, plaqueDepart, photoPath;
  final double? quantite, lat, lon;
  final DateTime date;
  final String statut;
  final int? score;
  final List<TransLine> transbordements;
  final ArriveeLine? arrivee;
  const LotDetail({
    required this.id,
    required this.sessionId,
    required this.mineId,
    required this.reference,
    required this.couleur,
    required this.plaqueDepart,
    required this.photoPath,
    required this.quantite,
    required this.lat,
    required this.lon,
    required this.date,
    required this.statut,
    required this.score,
    required this.transbordements,
    required this.arrivee,
  });
}

final lotDetailProvider =
    FutureProvider.autoDispose.family<LotDetail, String>((ref, lotId) async {
  final db = ref.watch(dbProvider);
  final l = await (db.select(db.lots)..where((t) => t.id.equals(lotId)))
      .getSingle();
  final session = await (db.select(db.chargements)
        ..where((t) => t.id.equals(l.sessionId)))
      .getSingleOrNull();
  final trans = await (db.select(db.transbordements)
        ..where((t) => t.lotId.equals(lotId))
        ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
      .get();
  final arr = await (db.select(db.arriveesDepot)
        ..where((t) => t.lotId.equals(lotId)))
      .getSingleOrNull();

  return LotDetail(
    id: l.id,
    sessionId: l.sessionId,
    mineId: l.mineId,
    reference: l.reference,
    couleur: l.couleur,
    plaqueDepart: l.plaqueDepart,
    photoPath: l.photoPath,
    quantite: l.quantiteEstimee,
    lat: l.gpsLat,
    lon: l.gpsLon,
    date: session?.dateCreation ?? DateTime.fromMillisecondsSinceEpoch(0),
    statut: l.statut,
    score: l.score ?? arr?.scoreTracabilite,
    transbordements: trans
        .map((t) => TransLine(t.ordre, t.plaqueAvant, t.plaqueApres, t.conforme,
            t.photoDechargePath, t.photoRechargePath))
        .toList(),
    arrivee: arr == null
        ? null
        : ArriveeLine(arr.depotId, arr.chauffeur, arr.numPermis, arr.numLot,
            arr.statutGps, arr.plaqueArrivee, arr.plaqueCoherente,
            arr.scoreTracabilite, arr.photoArriveePath, arr.photoPermisPath),
  );
});
