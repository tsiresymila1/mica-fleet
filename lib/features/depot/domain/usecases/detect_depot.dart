import '../../../../core/utils/geo.dart';
import '../entities/depot.dart';

/// Un dépôt candidat avec la distance mesurée et le verdict de zone.
typedef DepotProche = ({Depot depot, double distanceMetres, String statutGps});

class DetectDepot {
  /// Retourne le dépôt actif dont la zone contient la position, ou null.
  Depot? call(List<Depot> depots, double lat, double lon) {
    for (final d in depots.where((d) => d.actif)) {
      if (_coordsValides(d) && isWithinRadius(lat, lon, d.lat, d.lon, d.rayonMetres)) {
        return d;
      }
    }
    return null;
  }

  /// Dépôt actif le plus proche + statut GPS, sans exiger d'être dans la zone :
  /// - `non_verifiable` : coordonnées du dépôt absentes côté serveur (0,0 ou
  ///   rayon 0) → position ni confirmée ni infirmée.
  /// - `valide` : dans le rayon.
  /// - `hors_zone` : hors du rayon (position suspecte).
  /// Null seulement si aucun dépôt actif dans le référentiel.
  DepotProche? nearest(List<Depot> depots, double lat, double lon) {
    final actifs = depots.where((d) => d.actif).toList();
    if (actifs.isEmpty) return null;
    actifs.sort((a, b) => haversineMeters(lat, lon, a.lat, a.lon)
        .compareTo(haversineMeters(lat, lon, b.lat, b.lon)));
    final d = actifs.first;
    final dist = haversineMeters(lat, lon, d.lat, d.lon);
    final statut = !_coordsValides(d)
        ? 'non_verifiable'
        : dist <= d.rayonMetres
            ? 'valide'
            : 'hors_zone';
    return (depot: d, distanceMetres: dist, statutGps: statut);
  }

  /// Coordonnées exploitables : rayon > 0 et pas le point nul (0,0).
  static bool _coordsValides(Depot d) =>
      d.rayonMetres > 0 && !(d.lat == 0 && d.lon == 0);
}
