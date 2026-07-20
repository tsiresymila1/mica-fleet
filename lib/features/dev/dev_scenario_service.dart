import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/db/app_database.dart';
import '../../core/utils/location.dart';
import '../../core/utils/loading_id.dart';

/// Outils de test (DEBUG uniquement) pour simuler des scénarios sur un vrai
/// appareil sans se déplacer : placer les mines/dépôts autour de soi, injecter
/// des chargements de démonstration avec des états variés.
class DevScenarioService {
  final AppDatabase db;
  DevScenarioService(this.db);

  /// Place 3 mines + 1 dépôt autour de la position actuelle (rayon large) pour
  /// que la validation GPS passe partout où l'on se trouve.
  Future<({double lat, double lon})> seedAroundMe() async {
    await ensureLocationReady();
    final p = await Geolocator.getCurrentPosition();
    const r = Value(80.0); // rayon large : tolère la dérive GPS
    final mines = [
      ('M001', 'Mine Test A', p.latitude, p.longitude),
      ('M002', 'Mine Test B', p.latitude + 0.00005, p.longitude),
      ('M003', 'Mine Test C', p.latitude, p.longitude + 0.00005),
    ];
    for (final (id, nom, lat, lon) in mines) {
      await db.into(db.mines).insertOnConflictUpdate(MinesCompanion.insert(
          id: id, nom: nom, lat: lat, lon: lon, rayonMetres: r));
    }
    await db.into(db.depots).insertOnConflictUpdate(DepotsCompanion.insert(
        id: 'D001',
        nom: 'Dépôt Test (ici)',
        lat: p.latitude,
        lon: p.longitude,
        rayonMetres: r));
    return (lat: p.latitude, lon: p.longitude);
  }

  /// Injecte 3 chargements de démo : score 100 (arrivé), score 60 (arrivé),
  /// et un « en cours » (supprimable). Pour tester la liste / détail / score.
  Future<void> injectDemoChargements(String fournisseurId) async {
    await db.into(db.depots).insertOnConflictUpdate(DepotsCompanion.insert(
        id: 'DEMO', nom: 'Dépôt Démo', lat: -18.879, lon: 47.508));

    // Une session par scénario, avec UN lot (1 mine = 1 lot = 1 traçabilité).
    Future<void> mk(int seq, int? score, bool arrive, String couleur) async {
      final sessionId = buildLoadingId(2026, 900 + seq);
      final lotId = '$sessionId-L1';
      await db.into(db.chargements).insertOnConflictUpdate(
          ChargementsCompanion.insert(
              id: sessionId,
              fournisseurId: fournisseurId,
              dateCreation: DateTime(2026, 6, 20 + seq, 8),
              statut: const Value('valide')));
      await db.into(db.lots).insertOnConflictUpdate(LotsCompanion.insert(
          id: lotId,
          sessionId: sessionId,
          mineId: 'M001',
          couleur: Value(couleur),
          quantiteEstimee: const Value(120),
          plaqueDepart: Value('12${seq}4 TBR'),
          statut: Value(arrive ? 'arrive' : 'en_cours'),
          score: Value(score),
          deviceUuid: Value('demo-uuid-$seq')));
      if (arrive) {
        await db.into(db.arriveesDepot).insertOnConflictUpdate(
            ArriveesDepotCompanion.insert(
                lotId: lotId,
                depotId: 'DEMO',
                chauffeur: 'Rakoto',
                numPermis: 'P-$seq',
                numLot: 'LOT-$seq',
                gpsLat: -18.879,
                gpsLon: 47.508,
                statutGps: 'valide',
                scoreTracabilite: Value(score)));
      }
    }

    await mk(1, 100, true, 'Blanc');
    await mk(2, 60, true, 'Doré');
    await mk(3, null, false, 'Vert');
  }

  /// Coordonnées départ (mine M001) et dépôt (D001) pour la simulation guidée.
  Future<({double dLat, double dLon, double aLat, double aLon})?>
      simEndpoints() async {
    final mine = await (db.select(db.mines)..where((m) => m.id.equals('M001')))
        .getSingleOrNull();
    final depot = await (db.select(db.depots)..where((d) => d.id.equals('D001')))
        .getSingleOrNull();
    if (mine == null || depot == null) return null;
    return (dLat: mine.lat, dLon: mine.lon, aLat: depot.lat, aLon: depot.lon);
  }

  /// Vide tous les chargements (et données liées) — remise à zéro rapide.
  Future<void> clearChargements() async {
    await db.transaction(() async {
      await db.delete(db.arriveesDepot).go();
      await db.delete(db.transbordements).go();
      await db.delete(db.lots).go();
      await db.delete(db.syncQueue).go();
      await db.delete(db.chargements).go();
    });
  }
}
