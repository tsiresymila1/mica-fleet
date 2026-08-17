import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';

class PhotoLine {
  final String label;
  final String path;
  const PhotoLine(this.label, this.path);
}

class TransLine {
  final int ordre;
  final String? plaqueAvant, plaqueApres, photoDecharge, photoRecharge;
  final List<PhotoLine> photosDecharge, photosRecharge;
  final bool conforme;
  const TransLine(
    this.ordre,
    this.plaqueAvant,
    this.plaqueApres,
    this.conforme,
    this.photoDecharge,
    this.photoRecharge,
    this.photosDecharge,
    this.photosRecharge,
  );
}

class ArriveeLine {
  final String? depotId;
  final String chauffeur, numPermis, numLot, statutGps;
  final String? plaqueArrivee, photoArrivee, photoPermis;
  final List<PhotoLine> photosDecharge;
  final bool plaqueCoherente;
  final int? score;
  const ArriveeLine(
    this.depotId,
    this.chauffeur,
    this.numPermis,
    this.numLot,
    this.statutGps,
    this.plaqueArrivee,
    this.plaqueCoherente,
    this.score,
    this.photoArrivee,
    this.photoPermis,
    this.photosDecharge,
  );
}

/// État de synchronisation d'un lot vers Odoo, du point de vue de l'agent.
enum SyncEtat {
  local, // pas encore prêt à partir (lot en cours) ou aucune op
  enAttente, // arrivé, en file d'envoi
  echec, // 5 tentatives échouées → renvoi manuel
  envoiPhotos, // données envoyées, photos encore à monter
  synchronise, // tout est côté serveur
}

/// Dérive l'état affiché depuis le statut de l'op de sync du lot et le fait
/// que ses photos soient montées. `opStatus` null = aucune op (lot local).
SyncEtat syncEtatFrom(String? opStatus, bool photosUploaded) =>
    switch (opStatus) {
      null => SyncEtat.local,
      'failed' => SyncEtat.echec,
      'synced' => photosUploaded ? SyncEtat.synchronise : SyncEtat.envoiPhotos,
      _ => SyncEtat.enAttente, // pending / syncing
    };

/// Détail d'UN LOT : origine (une mine), ses transbordements, son arrivée.
class LotDetail {
  final String id;
  final String sessionId;
  final String mineId;
  final String mineName;
  final String? reference, couleur, plaqueDepart, photoPath;
  final double? quantite, lat, lon;
  final DateTime date;
  final String statut;
  final int? score;
  final List<PhotoLine> minePhotos;
  final List<TransLine> transbordements;
  final ArriveeLine? arrivee;
  final SyncEtat sync;
  final String validationStatus;
  final String? validationReason;
  final String? serverReference;
  final bool remoteOnly;
  const LotDetail({
    required this.id,
    required this.sessionId,
    required this.mineId,
    required this.mineName,
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
    required this.minePhotos,
    required this.transbordements,
    required this.arrivee,
    required this.sync,
    required this.validationStatus,
    required this.validationReason,
    required this.serverReference,
    required this.remoteOnly,
  });

  /// Renvoi manuel possible : arrivé mais pas totalement synchronisé.
  bool get renvoyable =>
      sync == SyncEtat.enAttente ||
      sync == SyncEtat.echec ||
      sync == SyncEtat.envoiPhotos;
}

final lotDetailProvider = FutureProvider.autoDispose.family<LotDetail, String>((
  ref,
  lotId,
) async {
  final db = ref.watch(dbProvider);
  final l = await (db.select(
    db.lots,
  )..where((t) => t.id.equals(lotId))).getSingle();
  final session = await (db.select(
    db.chargements,
  )..where((t) => t.id.equals(l.sessionId))).getSingleOrNull();
  final mine = await (db.select(
    db.mines,
  )..where((t) => t.id.equals(l.mineId))).getSingleOrNull();
  final trans =
      await (db.select(db.transbordements)
            ..where((t) => t.lotId.equals(lotId))
            ..orderBy([(t) => OrderingTerm.asc(t.ordre)]))
          .get();
  final arr = await (db.select(
    db.arriveesDepot,
  )..where((t) => t.lotId.equals(lotId))).getSingleOrNull();
  final photoRows = await (db.select(
    db.lotTraceabilityPhotos,
  )..where((t) => t.lotId.equals(lotId))).get();
  List<PhotoLine> photos(String stage, int order) => photoRows
      .where((row) => row.stage == stage && row.stageOrder == order)
      .map((row) => PhotoLine(_photoRoleLabel(row.role), row.path))
      .toList();

  // Op de sync de ce lot (créée à l'arrivée). En dériver l'état affiché.
  final op =
      await (db.select(db.syncQueue)..where(
            (t) => t.entityId.equals(lotId) & t.entityType.equals('lot'),
          ))
          .getSingleOrNull();
  final sync = l.remoteOnly
      ? SyncEtat.synchronise
      : syncEtatFrom(op?.status, l.photosUploaded);

  return LotDetail(
    id: l.id,
    sessionId: l.sessionId,
    mineId: l.mineId,
    mineName: mine?.nom ?? l.mineId,
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
    minePhotos: photos('mine', 0),
    transbordements: trans
        .map(
          (t) => TransLine(
            t.ordre,
            t.plaqueAvant,
            t.plaqueApres,
            t.conforme,
            t.photoDechargePath,
            t.photoRechargePath,
            photos('transload_unload', t.ordre),
            photos('transload_reload', t.ordre),
          ),
        )
        .toList(),
    arrivee: arr == null
        ? null
        : ArriveeLine(
            arr.depotId,
            arr.chauffeur,
            arr.numPermis,
            arr.numLot,
            arr.statutGps,
            arr.plaqueArrivee,
            arr.plaqueCoherente,
            arr.scoreTracabilite,
            arr.photoArriveePath,
            arr.photoPermisPath,
            photos('depot_unload', 0),
          ),
    sync: sync,
    validationStatus: l.validationStatus,
    validationReason: l.validationReason,
    serverReference: l.serverReference,
    remoteOnly: l.remoteOnly,
  );
});

String _photoRoleLabel(String role) => switch (role) {
  'plate' => 'Plaque',
  'mica' => 'Mica',
  'truck_with_mica' => 'Camion + mica',
  _ => role,
};
