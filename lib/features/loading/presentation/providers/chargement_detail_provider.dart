import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';

class MineLine {
  final String mineId;
  final String? couleur, plaque, photoPath;
  final double? quantite, lat, lon;
  const MineLine(this.mineId, this.couleur, this.plaque, this.quantite,
      this.lat, this.lon, this.photoPath);
}

class TransLine {
  final int ordre;
  final String? plaqueAvant, plaqueApres;
  final bool conforme;
  const TransLine(this.ordre, this.plaqueAvant, this.plaqueApres, this.conforme);
}

class ArriveeLine {
  final String depotId, chauffeur, numPermis, numLot;
  final String? plaqueArrivee, lotsJson;
  final bool plaqueCoherente;
  final int? score;
  const ArriveeLine(this.depotId, this.chauffeur, this.numPermis, this.numLot,
      this.plaqueArrivee, this.lotsJson, this.plaqueCoherente, this.score);
}

class ChargementDetail {
  final String id;
  final DateTime date;
  final String statut;
  final List<MineLine> mines;
  final List<TransLine> transbordements;
  final ArriveeLine? arrivee;
  const ChargementDetail(this.id, this.date, this.statut, this.mines,
      this.transbordements, this.arrivee);
}

final chargementDetailProvider = FutureProvider.autoDispose
    .family<ChargementDetail, String>((ref, chargementId) async {
  final db = ref.watch(dbProvider);
  final c = await (db.select(db.chargements)
        ..where((t) => t.id.equals(chargementId)))
      .getSingle();
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

  return ChargementDetail(
    c.id,
    c.dateCreation,
    c.statut,
    mines
        .map((m) => MineLine(m.mineId, m.couleur, m.plaqueOcr, m.quantiteEstimee,
            m.gpsLat, m.gpsLon, m.photoPath))
        .toList(),
    trans
        .map((t) =>
            TransLine(t.ordre, t.plaqueAvant, t.plaqueApres, t.conforme))
        .toList(),
    arr == null
        ? null
        : ArriveeLine(arr.depotId, arr.chauffeur, arr.numPermis, arr.numLot,
            arr.plaqueArrivee, arr.lotsJson, arr.plaqueCoherente,
            arr.scoreTracabilite),
  );
});
